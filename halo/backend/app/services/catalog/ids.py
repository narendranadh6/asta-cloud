"""Halo track ids: ``<source>:<id at that source>``, e.g. ``audius:D7KyD``, ``jamendo:1532771``."""

from __future__ import annotations

import re
from typing import Literal, cast

TrackSource = Literal["audius", "jamendo", "itunes"]
SOURCES: tuple[TrackSource, ...] = ("audius", "jamendo", "itunes")

_TRACK_ID = re.compile(r"^(audius|jamendo|itunes):([A-Za-z0-9_-]{1,40})$")
TRACK_ID_PATTERN = _TRACK_ID.pattern


def make_track_id(source: TrackSource, source_id: str) -> str:
    return f"{source}:{source_id}"


def is_valid_track_id(value: str) -> bool:
    return bool(_TRACK_ID.match(value or ""))


def parse_track_id(value: str) -> tuple[TrackSource, str]:
    match = _TRACK_ID.match(value or "")
    if not match:
        raise ValueError(f"Invalid track id: {value!r}")
    return cast(TrackSource, match.group(1)), match.group(2)
