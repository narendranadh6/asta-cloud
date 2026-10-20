"""LLM planner providers behind one interface, with a deterministic fallback.

The LLM is asked for a JSON object matching ``MusicIntent``. Its output is validated with
Pydantic; anything invalid (including URLs or video ids inside queries) falls back to the
heuristic planner. User text is never logged.
"""

from __future__ import annotations

import json
import logging
import re
from dataclasses import asdict, dataclass
from typing import Any, Literal, Protocol

import httpx
from pydantic import ValidationError

from app.services.ai.heuristic import PreferenceHints, extract_intent
from app.services.ai.intent import MusicIntent

logger = logging.getLogger("halo.ai")

SYSTEM_PROMPT = """You are Halo's music planning engine. Convert the listener's request into
a JSON object describing their intent and 2-5 music *search queries*.

Rules:
- Output ONLY one JSON object, no prose, no markdown fences.
- Never output URLs, video ids, playlist ids or claims that a specific video exists.
  Queries are plain search text (e.g. "Telugu melody songs 2000s"); Halo verifies results.
- mood must be one of: calm, happy, focused, energetic, romantic, sleep, workout, travel, or null.
- energy is 0-100. duration_minutes is 10-300. discovery is familiar|balanced|discovery.
- vocals is any|minimal|instrumental.
- Respect excluded artists: never build queries around them.
- explanation: one or two friendly sentences describing the plan, addressed to the listener.

JSON keys: mood, language, genres, activity, era, energy, vocals, duration_minutes,
discovery, reference_artists, exclude_artists, search_queries, playlist_title, explanation.
"""


class PlannerError(Exception):
    pass


class LLMClient(Protocol):
    async def complete_json(self, system: str, user: str) -> str: ...

    async def aclose(self) -> None: ...


class AnthropicClient:
    """Anthropic Messages API (https://docs.anthropic.com/en/api/messages)."""

    def __init__(
        self,
        api_key: str,
        model: str,
        *,
        base_url: str | None = None,
        timeout: float = 20.0,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        self._model = model
        self._client = http_client or httpx.AsyncClient(
            base_url=base_url or "https://api.anthropic.com",
            timeout=timeout,
            headers={"x-api-key": api_key, "anthropic-version": "2023-06-01"},
        )

    async def complete_json(self, system: str, user: str) -> str:
        response = await self._client.post(
            "/v1/messages",
            json={
                "model": self._model,
                "max_tokens": 1024,
                "system": system,
                "messages": [{"role": "user", "content": user}],
            },
        )
        if response.status_code != 200:
            raise PlannerError(f"LLM provider returned {response.status_code}")
        blocks = response.json().get("content", [])
        return "".join(b.get("text", "") for b in blocks if b.get("type") == "text")

    async def aclose(self) -> None:
        await self._client.aclose()


class OpenAICompatibleClient:
    """Any OpenAI-compatible /chat/completions endpoint (OpenAI, Azure, local servers)."""

    def __init__(
        self,
        api_key: str,
        model: str,
        *,
        base_url: str | None = None,
        timeout: float = 20.0,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        self._model = model
        self._client = http_client or httpx.AsyncClient(
            base_url=base_url or "https://api.openai.com/v1",
            timeout=timeout,
            headers={"Authorization": f"Bearer {api_key}"},
        )

    async def complete_json(self, system: str, user: str) -> str:
        response = await self._client.post(
            "/chat/completions",
            json={
                "model": self._model,
                "response_format": {"type": "json_object"},
                "messages": [
                    {"role": "system", "content": system},
                    {"role": "user", "content": user},
                ],
            },
        )
        if response.status_code != 200:
            raise PlannerError(f"LLM provider returned {response.status_code}")
        choices = response.json().get("choices", [])
        return str(choices[0]["message"]["content"]) if choices else ""

    async def aclose(self) -> None:
        await self._client.aclose()


_JSON_OBJECT = re.compile(r"\{.*\}", re.DOTALL)


def parse_intent_json(raw: str) -> MusicIntent:
    match = _JSON_OBJECT.search(raw or "")
    if not match:
        raise PlannerError("LLM response contained no JSON object")
    try:
        data: Any = json.loads(match.group(0))
    except json.JSONDecodeError as exc:
        raise PlannerError("LLM response was not valid JSON") from exc
    if not isinstance(data, dict):
        raise PlannerError("LLM response was not a JSON object")
    try:
        return MusicIntent.model_validate(data)
    except ValidationError as exc:
        raise PlannerError("LLM response failed schema validation") from exc


@dataclass(slots=True)
class PlanResult:
    intent: MusicIntent
    planner: Literal["llm", "heuristic"]
    warning: str | None = None


@dataclass(slots=True)
class PlanOverrides:
    mood: str | None = None
    language: str | None = None
    genres: list[str] | None = None
    energy: int | None = None
    duration_minutes: int | None = None
    discovery: str | None = None

    def explicit(self) -> dict[str, Any]:
        return {k: v for k, v in asdict(self).items() if v not in (None, [])}


class IntentPlanner:
    def __init__(self, llm: LLMClient | None) -> None:
        self._llm = llm

    @property
    def uses_llm(self) -> bool:
        return self._llm is not None

    async def aclose(self) -> None:
        if self._llm is not None:
            await self._llm.aclose()

    async def plan(
        self,
        text: str,
        hints: PreferenceHints,
        overrides: PlanOverrides | None = None,
        history: list[dict[str, str]] | None = None,
    ) -> PlanResult:
        overrides = overrides or PlanOverrides()
        if self._llm is not None:
            try:
                intent = await self._plan_with_llm(text, hints, overrides, history or [])
                return PlanResult(intent=intent, planner="llm")
            except (PlannerError, httpx.HTTPError, KeyError, IndexError, TypeError):
                logger.warning("LLM planner failed; using deterministic fallback")
                fallback = self._heuristic(text, hints, overrides)
                return PlanResult(
                    intent=fallback,
                    planner="heuristic",
                    warning="The AI planner was unavailable, so Halo used its built-in planner.",
                )
        return PlanResult(intent=self._heuristic(text, hints, overrides), planner="heuristic")

    @staticmethod
    def _heuristic(text: str, hints: PreferenceHints, o: PlanOverrides) -> MusicIntent:
        return extract_intent(
            text,
            hints,
            mood=o.mood,
            language=o.language,
            genres=o.genres,
            energy=o.energy,
            duration_minutes=o.duration_minutes,
            discovery=o.discovery,
        )

    async def _plan_with_llm(
        self, text: str, hints: PreferenceHints, o: PlanOverrides, history: list[dict[str, str]]
    ) -> MusicIntent:
        assert self._llm is not None
        context: dict[str, Any] = {
            "request": text,
            "recent_conversation": history[-6:],
            "listener_preferences": {
                "languages": hints.languages,
                "genres": hints.genres,
                "moods": hints.moods,
                "favorite_artists": hints.favorite_artists[:10],
                "excluded_artists": hints.excluded_artists[:20],
                "discovery": hints.discovery,
            },
            "explicit_settings": o.explicit(),
        }
        raw = await self._llm.complete_json(SYSTEM_PROMPT, json.dumps(context, ensure_ascii=False))
        intent = parse_intent_json(raw)
        # Explicit form settings always win over model interpretation.
        updates = o.explicit()
        merged_excludes = list(dict.fromkeys([*intent.exclude_artists, *hints.excluded_artists]))
        updates["exclude_artists"] = merged_excludes[:20]
        return intent.model_copy(update=updates)


def build_planner(settings: object) -> IntentPlanner:
    from app.core.config import Settings

    assert isinstance(settings, Settings)
    key = settings.llm_api_key.get_secret_value() if settings.llm_api_key else ""
    if settings.llm_provider == "none" or not key:
        return IntentPlanner(None)
    client: LLMClient
    if settings.llm_provider == "anthropic":
        client = AnthropicClient(
            key,
            settings.llm_model,
            base_url=settings.llm_base_url,
            timeout=settings.llm_timeout_seconds,
        )
    else:
        client = OpenAICompatibleClient(
            key,
            settings.llm_model,
            base_url=settings.llm_base_url,
            timeout=settings.llm_timeout_seconds,
        )
    return IntentPlanner(client)
