"""The optional AI fallback: off by default, consent-gated, output validated, bounded."""

from __future__ import annotations

import asyncio
import json

import httpx
import pytest

from app.services.ai.intent_fallback import (
    DisabledIntentFallback,
    IntentFallbackRequest,
    LLMIntentFallback,
    is_valid_operation,
    validate,
)


class FakeLLM:
    def __init__(self, replies: list[str | Exception], delay: float = 0.0) -> None:
        self.replies = replies
        self.delay = delay
        self.prompts: list[str] = []

    async def complete_json(self, system: str, user: str) -> str:
        self.prompts.append(user)
        if self.delay:
            await asyncio.sleep(self.delay)
        reply = self.replies.pop(0)
        if isinstance(reply, Exception):
            raise reply
        return reply

    async def aclose(self) -> None:
        return None


def test_vocabulary_matches_the_phone() -> None:
    for op in [
        "play",
        "play:artist:S. Thaman",
        "set:energy:0.85",
        "adjust:valence:-0.20",
        "lang:mostly:te+en",
        "recency:days:1",
        "recency:decade:1990",
        "exclude:currentTrack:session",
        "weight:last:-0.6",
        "avoid:sad",
        "ask:upNext",
        "undo",
        "play:genre:jazz",
        "preserve:vibe",
    ]:
        assert is_valid_operation(op), op
    for op in [
        "play:artist:",
        "set:energy:3",
        "lang:only:ta",
        "delete:everything",
        "transport:format",
        "recency:decade:1995",
        "exclude:x:forever",
        "play:any:https://evil.test/x",
        "play:song:" + "a" * 100,
    ]:
        assert not is_valid_operation(op), op


def test_model_output_is_accepted_only_whole_and_in_vocabulary() -> None:
    assert validate('{"outcome":"execute","operations":["play","lang:only:te"]}') == (
        "execute",
        ["play", "lang:only:te"],
    )
    assert validate('{"outcome":"unsupported","operations":[]}') == ("unsupported", [])
    assert validate("not json") is None
    assert (
        validate('{"outcome":"execute","operations":["play","rm -rf"]}') is None
    )  # one bad → none
    assert validate('{"outcome":"execute","operations":[]}') is None
    assert validate('{"outcome":"unsupported","operations":["play"]}') is None
    assert validate(json.dumps({"outcome": "execute", "operations": ["play"] * 7})) is None


async def test_only_the_command_text_is_sent_and_timeouts_are_bounded() -> None:
    llm = FakeLLM(['{"outcome":"execute","operations":["set:energy:0.85"]}'])
    fallback = LLMIntentFallback(llm, provider="fake")
    result = await fallback.interpret(
        IntentFallbackRequest(transcript="josh unna paatalu", consent=True)
    )
    assert result.operations == ["set:energy:0.85"]
    sent = json.loads(llm.prompts[0])
    assert set(sent) == {"command", "speech", "session_language"}  # nothing else leaves
    slow = LLMIntentFallback(
        FakeLLM(["{}", "{}"], delay=0.2), provider="fake", timeout_seconds=0.05, retries=1
    )
    timed_out = await slow.interpret(IntentFallbackRequest(transcript="x", consent=True))
    assert timed_out.outcome == "no_action" and timed_out.note == "timeout"
    assert timed_out.latency_ms < 1000
    junk = await LLMIntentFallback(FakeLLM(["I think you want jazz!"]), provider="fake").interpret(
        IntentFallbackRequest(transcript="x", consent=True)
    )
    assert junk.note == "invalid_model_output" and junk.operations == []


async def test_endpoint_needs_consent_and_is_off_by_default(
    client: httpx.AsyncClient, auth: dict[str, str]
) -> None:
    body = {"transcript": "something unclear", "consent": False}
    refused = await client.post("/api/v1/intent/fallback", json=body, headers=auth)
    assert refused.status_code == 403
    assert refused.json()["error"]["code"] == "consent_required"
    disabled = await client.post(
        "/api/v1/intent/fallback", json={**body, "consent": True}, headers=auth
    )
    assert disabled.status_code == 503
    assert disabled.json()["error"]["code"] == "fallback_disabled"
    too_long = await client.post(
        "/api/v1/intent/fallback", json={"transcript": "x" * 201, "consent": True}, headers=auth
    )
    assert too_long.status_code == 422


@pytest.mark.parametrize("fallback", [DisabledIntentFallback()])
async def test_disabled_fallback_does_nothing(fallback: DisabledIntentFallback) -> None:
    result = await fallback.interpret(IntentFallbackRequest(transcript="x", consent=True))
    assert result.outcome == "no_action" and result.operations == []
