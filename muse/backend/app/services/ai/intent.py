"""Structured music intent produced by the planner (LLM or deterministic fallback).

The planner only produces *search queries*. It is never trusted to produce video ids or
URLs: any query containing a URL-like token is rejected, and every playable reference
comes from validated metadata-provider results.
"""

from __future__ import annotations

import re
from typing import Literal

from pydantic import BaseModel, ConfigDict, Field, field_validator

Mood = Literal["calm", "happy", "focused", "energetic", "romantic", "sleep", "workout", "travel"]

_URLISH = re.compile(
    r"(https?://|www\.|youtube\.com|youtu\.be|\.com/|watch\?v=|[?&]v=|[?&]list=)",
    re.IGNORECASE,
)


class MusicIntent(BaseModel):
    model_config = ConfigDict(extra="ignore")

    mood: Mood | None = None
    language: str | None = Field(default=None, max_length=40)
    genres: list[str] = Field(default_factory=list, max_length=6)
    activity: str | None = Field(default=None, max_length=60)
    era: str | None = Field(default=None, max_length=20)
    energy: int = Field(default=50, ge=0, le=100)
    vocals: Literal["any", "minimal", "instrumental"] = "any"
    duration_minutes: int = Field(default=60, ge=10, le=300)
    discovery: Literal["familiar", "balanced", "discovery"] = "balanced"
    reference_artists: list[str] = Field(default_factory=list, max_length=8)
    exclude_artists: list[str] = Field(default_factory=list, max_length=20)
    search_queries: list[str] = Field(min_length=1, max_length=6)
    playlist_title: str = Field(default="MUSE Mix", min_length=1, max_length=80)
    explanation: str = Field(default="", max_length=600)

    @field_validator("language", "activity", "era", mode="before")
    @classmethod
    def _blank_to_none(cls, value: object) -> object:
        if isinstance(value, str) and not value.strip():
            return None
        return value

    @field_validator("genres", "reference_artists", "exclude_artists")
    @classmethod
    def _clean_list(cls, values: list[str]) -> list[str]:
        out: list[str] = []
        for value in values:
            cleaned = " ".join(str(value).split())[:60]
            if cleaned and cleaned.lower() not in {o.lower() for o in out}:
                out.append(cleaned)
        return out

    @field_validator("search_queries")
    @classmethod
    def _safe_queries(cls, values: list[str]) -> list[str]:
        out: list[str] = []
        for value in values:
            cleaned = " ".join(str(value).split())[:100]
            if not cleaned:
                continue
            if _URLISH.search(cleaned):
                raise ValueError("search queries must be plain text, never URLs or video ids")
            if cleaned.lower() not in {o.lower() for o in out}:
                out.append(cleaned)
        if not out:
            raise ValueError("at least one search query is required")
        return out

    def summary_fields(self) -> dict[str, object]:
        return self.model_dump(exclude={"explanation", "playlist_title"})


INTENT_JSON_SCHEMA = MusicIntent.model_json_schema()
