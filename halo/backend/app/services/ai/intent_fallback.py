"""Optional AI fallback for Halo Drive commands the phone's parser couldn't understand.

The phone's deterministic parser stays the primary path. Only when it can't act, and only
with the listener's consent, the app may send the *text* of one command (never audio, never
history) plus the session language. A language model proposes operations in Halo's wire
vocabulary; every string is validated against the same grammar the phone uses
(``SessionOperation(wire:)`` in the iOS app), and the phone then applies them through its own
session reducer and confirmation rules. The model never controls playback, never sees the
catalog, and can't bypass rights checks: playable songs still only come from catalog sources.

Disabled by default (``HALO_INTENT_FALLBACK_ENABLED``); needs an LLM provider configured. The
transcript is never logged.
"""

from __future__ import annotations

import asyncio
import json
import logging
import re
import time
from dataclasses import dataclass
from typing import Literal, Protocol

from pydantic import BaseModel, Field

from app.services.ai.intent import _URLISH
from app.services.ai.providers import LLMClient

logger = logging.getLogger("halo.ai.fallback")

Outcome = Literal["execute", "clarify", "unsupported", "no_action"]
MAX_OPERATIONS = 6

_NUM = r"(?:0(?:\.\d{1,2})?|1(?:\.0{1,2})?)"
_SIGNED = r"[+-]" + _NUM
_NAME = r"[^:\n]{1,80}"
_VOCABULARY = [
    r"play",
    r"play:(?:surprise|similar|current|currentAlbum)",
    rf"play:(?:artist|soundtrack|album|song|genre|any):{_NAME}",
    r"transport:(?:pause|resume|next|previous|restart|removeNext|stop)",
    rf"set:(?:energy|valence|tempo|discovery):{_NUM}",
    rf"adjust:(?:energy|valence|tempo|discovery):{_SIGNED}",
    r"lang:only:(?:te|en)",
    r"lang:(?:mostly|mixed|alternating):(?:te\+en|en\+te)",
    r"favor:(?:te|en)",
    r"recency:(?:any|classics)",
    r"recency:days:(?:[1-9]\d{0,2}|[1-3]\d{3})",
    r"recency:decade:(?:19|20)\d0",
    r"newer|older|lock|unlock|undo|diversify|avoid:sad",
    r"preserve:(?:vibe|language|artist|recency)(?:\+(?:vibe|language|artist|recency))*",
    r"seed:(?:similar|deeper|elsewhere)",
    rf"weight:(?:current|last|{_NAME}):{_SIGNED}",
    rf"exclude:(?:current|last|currentTrack|{_NAME}):(?:session|today|profile)",
    r"rate:(?:keep|like|dislike|neverAgain|later)",
    r"ask:(?:whoIsSinging|whatMovie|whatAlbum|whenReleased|upNext)",
]
_GRAMMAR = re.compile("^(?:" + "|".join(f"(?:{v})" for v in _VOCABULARY) + ")$")

SYSTEM_PROMPT = """You map ONE voice command for a music player to operations. Reply with ONLY a
JSON object: {"outcome": "execute|clarify|unsupported|no_action", "operations": [...]}.
Use only these operation strings: play; play:surprise; play:similar; play:artist:<name>;
play:soundtrack:<film>; play:album:<name>; play:song:<title>; play:genre:<genre>;
transport:pause|resume|next|previous|restart|removeNext; set:energy|valence|tempo|discovery:<0..1>;
adjust:energy|valence|tempo|discovery:<-1..+1 with sign>; lang:only:te|en; lang:mixed:te+en;
lang:mostly:te+en; favor:te|en; recency:days:<n>; recency:decade:<1990>; recency:classics;
newer; older; lock; preserve:vibe; seed:elsewhere|deeper; weight:current|last|<artist>:<-1..+1>;
exclude:current|currentTrack|<artist>:session|today|profile; avoid:sad;
rate:like|dislike|neverAgain|later|keep;
ask:whoIsSinging|whatMovie|whatAlbum|whenReleased|upNext; undo.
Rules: never invent songs or artists; only use names the listener said. Anything not about
music is "unsupported" with no operations. If unsure, use "clarify" with no operations.
Telugu, romanized Telugu and English may be mixed."""


class IntentFallbackRequest(BaseModel):
    """The minimum the phone sends: one command's text, never audio or history."""

    transcript: str = Field(min_length=1, max_length=200)
    speech: Literal["english", "telugu", "mixed"] = "english"
    language: Literal["te", "en"] | None = None
    # The listener agreed to send unclear commands to Halo's server (Settings › Voice & privacy).
    consent: bool = False


class IntentFallbackResponse(BaseModel):
    outcome: Outcome
    operations: list[str] = Field(default_factory=list, max_length=MAX_OPERATIONS)
    provider: str
    latency_ms: int
    # Why the result is empty when it is ("invalid_model_output", "timeout", ...).
    note: str | None = None


def is_valid_operation(operation: str) -> bool:
    if len(operation) > 120 or _URLISH.search(operation):
        return False
    return bool(_GRAMMAR.match(operation))


def validate(raw: str) -> tuple[Outcome, list[str]] | None:
    """The model's JSON, if and only if every part is inside the vocabulary."""
    try:
        data = json.loads(raw.strip().removeprefix("```json").removesuffix("```"))
    except (json.JSONDecodeError, ValueError):
        return None
    if not isinstance(data, dict):
        return None
    outcome = data.get("outcome")
    operations = data.get("operations", [])
    if outcome not in ("execute", "clarify", "unsupported", "no_action"):
        return None
    if not isinstance(operations, list) or len(operations) > MAX_OPERATIONS:
        return None
    if not all(isinstance(o, str) and is_valid_operation(o) for o in operations):
        return None
    if outcome == "execute" and not operations:
        return None
    if outcome != "execute" and operations:
        return None
    return outcome, operations


class IntentFallback(Protocol):
    @property
    def enabled(self) -> bool: ...

    async def interpret(self, request: IntentFallbackRequest) -> IntentFallbackResponse: ...


class DisabledIntentFallback:
    enabled = False

    async def interpret(self, request: IntentFallbackRequest) -> IntentFallbackResponse:
        return IntentFallbackResponse(
            outcome="no_action", provider="none", latency_ms=0, note="disabled"
        )


@dataclass
class LLMIntentFallback:
    client: LLMClient
    provider: str
    timeout_seconds: float = 3.0
    retries: int = 1
    enabled: bool = True

    async def interpret(self, request: IntentFallbackRequest) -> IntentFallbackResponse:
        user = json.dumps(
            {
                "command": request.transcript,
                "speech": request.speech,
                "session_language": request.language,
            },
            ensure_ascii=False,
        )
        started = time.monotonic()
        note = "unavailable"
        for _attempt in range(self.retries + 1):
            try:
                raw = await asyncio.wait_for(
                    self.client.complete_json(SYSTEM_PROMPT, user), timeout=self.timeout_seconds
                )
            except TimeoutError:
                note = "timeout"
                continue
            except Exception:  # provider errors: logged without the transcript
                logger.warning("intent fallback provider failed", exc_info=False)
                note = "provider_error"
                continue
            elapsed = int((time.monotonic() - started) * 1000)
            parsed = validate(raw)
            if parsed is None:
                # Never retried: a model that answers outside the vocabulary gets no second try.
                return IntentFallbackResponse(
                    outcome="no_action",
                    provider=self.provider,
                    latency_ms=elapsed,
                    note="invalid_model_output",
                )
            outcome, operations = parsed
            return IntentFallbackResponse(
                outcome=outcome, operations=operations, provider=self.provider, latency_ms=elapsed
            )
        elapsed = int((time.monotonic() - started) * 1000)
        return IntentFallbackResponse(
            outcome="no_action", provider=self.provider, latency_ms=elapsed, note=note
        )


def build_intent_fallback(settings: object, client: LLMClient | None) -> IntentFallback:
    from app.core.config import Settings

    assert isinstance(settings, Settings)
    if not settings.intent_fallback_enabled or client is None:
        return DisabledIntentFallback()
    return LLMIntentFallback(
        client,
        provider=settings.llm_provider,
        timeout_seconds=settings.intent_fallback_timeout_seconds,
    )
