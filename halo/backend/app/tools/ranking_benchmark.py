"""Reproducible ranking benchmark: Halo Drive's session ranker v2 versus Flow 2.0 (v3).

    python -m app.tools.ranking_benchmark            # full run, prints a table and JSON
    python -m app.tools.ranking_benchmark --quick    # smaller run (used by the tests)

SYNTHETIC. There is no authorised real listening data yet, so this uses a seeded synthetic
catalog (artists with a long-tail song count, languages, energy, valence, release years) and
scripted listeners with hidden likes and dislikes. It measures how each ranker behaves under
the same sessions; it does not show that real listeners prefer either one.

Both versions get the same explicit session (language, vibe, exclusions, "no sad songs"). They
differ only in what the phone sends from listening, mirroring each app version:
  v2: every skip is −0.1 on the artist, uncapped, mixed into the explicit weights.
  v3: early skip −0.1, late skip −0.03, completion +0.05, replay +0.15, capped at ±0.4 and
      overridden by explicit weights; the last four artists are sent as `recent_artists`
      (v3 uses the last one for spacing). Ablations isolate spacing and a variety weight.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import math
import random
import re
from dataclasses import dataclass, field
from datetime import date
from typing import Any, Literal

from app.core.cache import MemoryStore
from app.schemas import AlbumPage, ArtistPage, Attribution, SessionCandidatesRequest, Track
from app.services.catalog.service import CatalogService
from app.services.recommendations.session import (
    SESSION_V2,
    SESSION_V3,
    RankingConfig,
    SessionRecommender,
    artist_matches,
)

SEED = 20261104
TODAY = date(2026, 6, 1)
_WORDS = re.compile(r"[a-z0-9]+")
_LANGUAGE_WORD = {"te": "telugu", "en": "english", "hi": "hindi"}


# --- Synthetic catalog --------------------------------------------------------------------


def build_catalog(rng: random.Random, artists: int = 50) -> list[tuple[Track, set[str]]]:
    catalog: list[tuple[Track, set[str]]] = []
    for a in range(artists):
        name = f"Artist {a:02d}"
        language = rng.choices(["te", "en", "hi"], weights=[6, 3, 1])[0]
        base_energy = rng.random()
        base_valence = rng.random()
        songs = max(3, round(60 / (a + 1)) + 3)  # a few prolific artists, a long tail
        for s in range(songs):
            energy = min(max(base_energy + rng.gauss(0, 0.15), 0), 1)
            valence = (
                None
                if rng.random() < 0.3
                else round(min(max(base_valence + rng.gauss(0, 0.2), 0), 1), 2)
            )
            year = rng.randint(1985, 2026)
            sid = f"a{a:02d}s{s:02d}"
            words = {_LANGUAGE_WORD[language], *name.lower().split(), str(year)[2:] + "s"}
            words |= (
                {"energetic", "dance"}
                if energy >= 0.65
                else {"calm", "melody"}
                if energy <= 0.35
                else set()
            )
            if valence is not None and valence >= 0.7:
                words.add("happy")
            if year >= 2025:
                words.add("new")
            words.add(f"{(year % 100) // 10 * 10:02d}s")
            track = Track(
                id=f"audius:{sid}",
                source="audius",
                source_id=sid,
                title=f"Song {sid}",
                artist=name,
                stream_url=f"https://stream.test/{sid}.mp3",
                release_date=f"{year}-0{1 + s % 9}-15",
                play_count=int(math.exp(rng.gauss(9, 2))),
                language=language,
                energy=round(energy, 2),
                valence=valence,
                attribution=Attribution(provider="audius", label="Audius"),
            )
            catalog.append((track, words))
    return catalog


class SyntheticSource:
    name: Literal["audius"] = "audius"
    full_tracks = True

    def __init__(self, catalog: list[tuple[Track, set[str]]]) -> None:
        self._catalog = catalog

    async def search(self, query: str, *, limit: int, offset: int = 0) -> list[Track]:
        words = set(_WORDS.findall(query.lower()))
        scored = [(len(words & tokens), -i, t) for i, (t, tokens) in enumerate(self._catalog)]
        hits = sorted((s for s in scored if s[0] > 0), key=lambda s: (s[0], s[1]), reverse=True)
        return [t for _, _, t in hits[offset : offset + limit]]

    async def trending(self, *, limit: int, genre: str | None = None) -> list[Track]:
        return sorted((t for t, _ in self._catalog), key=lambda t: t.play_count or 0, reverse=True)[
            :limit
        ]

    async def get_tracks(self, source_ids: list[str]) -> dict[str, Track]:
        wanted = set(source_ids)
        return {t.source_id: t for t, _ in self._catalog if t.source_id in wanted}

    async def get_artist(self, source_id: str) -> ArtistPage | None:
        return None

    async def get_album(self, source_id: str) -> AlbumPage | None:
        return None

    async def aclose(self) -> None:
        return None


# --- Scripted sessions ----------------------------------------------------------------------


@dataclass
class Listener:
    likes: set[str]
    dislikes: set[str]


@dataclass
class Scenario:
    name: str
    turns: list[dict[str, Any]]  # explicit session fields, applied cumulatively


def scenarios(
    rng: random.Random, catalog: list[tuple[Track, set[str]]]
) -> list[tuple[Scenario, Listener]]:
    by_language: dict[str, list[str]] = {}
    for track, _ in catalog:
        by_language.setdefault(track.language or "", []).append(track.artist)
    telugu = sorted(set(by_language["te"]))
    english = sorted(set(by_language["en"]))
    plans = [
        Scenario(
            "telugu-energetic", [{"language": {"primary": "te"}, "vibe": {"energy": 0.85}}] * 4
        ),
        Scenario(
            "telugu-calm-no-sad",
            [
                {"language": {"primary": "te"}, "vibe": {"energy": 0.2}},
                {"excluded_moods": ["sad"]},
                {},
                {},
            ],
        ),
        Scenario(
            "english-then-telugu",
            [
                {"language": {"primary": "en"}, "vibe": {"energy": 0.6}},
                {},
                {"language": {"primary": "te"}},
                {},
            ],
        ),
        Scenario(
            "mostly-telugu-some-english",
            [
                {
                    "language": {"primary": "te", "secondary": "en", "strategy": "mostly"},
                    "vibe": {"energy": 0.7},
                },
                {},
                {},
                {},
            ],
        ),
        Scenario(
            "exclude-prolific-artist",
            [
                {"language": {"primary": "te"}},
                {"excluded_artists": [telugu[0]]},
                {},
                {},
            ],
        ),
        Scenario(
            "nineties-telugu",
            [{"language": {"primary": "te"}, "recency": {"mode": "decade", "value": 1990}}] * 4,
        ),
        Scenario(
            "new-english-discovery",
            [
                {"language": {"primary": "en"}, "recency": {"mode": "within_days", "value": 365}},
                {"vibe": {"discovery": 0.8}},
                {},
                {},
            ],
        ),
        Scenario(
            "more-energy-steps",
            [
                {"language": {"primary": "te"}, "vibe": {"energy": 0.4}},
                {"vibe": {"energy": 0.6}},
                {"vibe": {"energy": 0.8}},
                {},
            ],
        ),
    ]
    paired = []
    for plan in plans:
        pool = telugu if "english" not in plan.name else english
        likes = set(rng.sample(pool, min(3, len(pool))))
        dislikes = set(rng.sample([a for a in pool if a not in likes], min(3, len(pool) - 3)))
        paired.append((plan, Listener(likes, dislikes)))
    return paired


# --- Simulation -------------------------------------------------------------------------------


@dataclass
class PhoneState:
    explicit_weights: dict[str, float] = field(default_factory=dict)
    inferred: dict[str, float] = field(default_factory=dict)
    recent: list[str] = field(default_factory=list)  # what the v3 phone sends
    heard: list[str] = field(default_factory=list)  # every artist heard, for measuring both
    played: list[str] = field(default_factory=list)


def _key(name: str) -> str:
    return " ".join(_WORDS.findall(name.lower()))


def relevant(track: Track, session: dict[str, Any], listener: Listener) -> bool:
    """Hidden truth: fits every explicit request and isn't an artist the listener dislikes."""
    if not satisfies_constraints(track, session):
        return False
    if track.artist in listener.dislikes:
        return False
    target = (session.get("vibe") or {}).get("energy")
    if target is not None and track.energy is not None and abs(track.energy - target) > 0.25:
        return False
    recency = session.get("recency") or {}
    year = int((track.release_date or "0")[:4])
    if recency.get("mode") == "decade" and not (recency["value"] <= year < recency["value"] + 10):
        return False
    if recency.get("mode") == "within_days" and year < TODAY.year - 1:
        return False
    return True


def satisfies_constraints(track: Track, session: dict[str, Any]) -> bool:
    language = session.get("language")
    if (
        language
        and language.get("strategy", "only") == "only"
        and track.language not in (None, language["primary"])
    ):
        return False
    if any(artist_matches(track.artist, _key(a)) for a in session.get("excluded_artists", [])):
        return False
    return not (
        "sad" in session.get("excluded_moods", [])
        and track.valence is not None
        and track.valence <= 0.3
    )


# Ablations of v3, to see which part moves which metric. They use v3's phone signals.
ABLATIONS: dict[str, RankingConfig] = {
    "v3-no-spacing": RankingConfig("v3-no-spacing", SESSION_V3.weights),
    "v3+variety": RankingConfig(
        "v3+variety",
        {**SESSION_V3.weights, "variety": 0.5},
        spacing_margin=SESSION_V3.spacing_margin,
    ),
}


def build_request(
    version: str, session: dict[str, Any], phone: PhoneState
) -> SessionCandidatesRequest:
    if version == "v2":
        weights = dict(phone.inferred)  # v2: inferred and explicit in one map
        weights.update({k: weights.get(k, 0) + v for k, v in phone.explicit_weights.items()})
        recent: list[str] = []
    else:
        weights = {**phone.inferred, **phone.explicit_weights}  # explicit wins
        recent = phone.recent[-4:]
    weights = {k: max(min(v, 5), -5) for k, v in list(weights.items())[:30]}
    return SessionCandidatesRequest.model_validate(
        {
            **{
                k: v
                for k, v in session.items()
                if k in ("language", "recency", "excluded_artists", "excluded_moods")
            },
            "vibe": session.get("vibe", {}),
            "artist_weights": weights,
            "recent_artists": recent,
            "excluded_track_ids": phone.played[-200:],
            "limit": 20,
        }
    )


def listen(
    version: str, track: Track, session: dict[str, Any], listener: Listener, phone: PhoneState
) -> str:
    """What the scripted listener does with the next song, and the signal the phone records."""
    name = _key(track.artist)
    if (
        track.artist in listener.dislikes
        or not relevant(track, session, listener)
        and track.artist not in listener.likes
    ):
        early = track.artist in listener.dislikes
        outcome = "early_skip" if early else "late_skip"
    else:
        outcome = "replay" if track.artist in listener.likes else "complete"
    if version == "v2":
        if outcome in ("early_skip", "late_skip"):
            phone.inferred[name] = phone.inferred.get(name, 0) - 0.1
    else:
        change = {"early_skip": -0.1, "late_skip": -0.03, "complete": 0.05, "replay": 0.2}[outcome]
        if outcome == "replay":
            change = 0.05 + 0.15  # completed, then replayed
        phone.inferred[name] = max(min(phone.inferred.get(name, 0) + change, 0.4), -0.4)
        phone.recent = [a for a in phone.recent if a != name] + [name]
    phone.played.append(track.id)
    phone.heard.append(name)
    return outcome


async def run(quick: bool = False) -> dict[str, Any]:
    rng = random.Random(SEED)
    catalog = build_catalog(rng, artists=30 if quick else 50)
    service = CatalogService([SyntheticSource(catalog)], MemoryStore())
    plans = scenarios(rng, catalog)
    results: dict[str, Any] = {
        "synthetic": True,
        "seed": SEED,
        "tracks": len(catalog),
        "versions": {},
    }
    configs: dict[str, RankingConfig] = {"v2": SESSION_V2, "v3": SESSION_V3, **ABLATIONS}
    for version, config in configs.items():
        recommender = SessionRecommender(service, today=TODAY, config=config)
        totals: dict[str, float] = {}
        count = 0
        plays: dict[str, int] = {}
        for plan, listener in plans:
            session: dict[str, Any] = {}
            phone = PhoneState()
            for turn in plan.turns:
                for key, value in turn.items():
                    session[key] = (
                        {**session.get(key, {}), **value} if isinstance(value, dict) else value
                    )
                response = await recommender.candidates(build_request(version, session, phone))
                top = [c.track for c in response.candidates[:10]]
                if not top:
                    continue
                metrics = measure(top, session, listener, phone)
                for name, value in metrics.items():
                    totals[name] = totals.get(name, 0) + value
                count += 1
                for track in top[:5]:  # the listener hears the next five
                    outcome = listen(version, track, session, listener, phone)
                    plays[outcome] = plays.get(outcome, 0) + 1
        heard = sum(plays.values()) or 1
        summary = {name: round(value / max(count, 1), 3) for name, value in totals.items()}
        summary["skip_rate"] = round(
            (plays.get("early_skip", 0) + plays.get("late_skip", 0)) / heard, 3
        )
        summary["turns"] = count
        results["versions"][config.version] = summary
    return results


def measure(
    top: list[Track], session: dict[str, Any], listener: Listener, phone: PhoneState
) -> dict[str, float]:
    artists = [t.artist for t in top]
    recent = set(phone.heard[-4:])
    return {
        "relevance_at_10": sum(relevant(t, session, listener) for t in top) / len(top),
        "unique_artists_at_10": len(set(artists)) / len(top),
        "adjacent_same_artist": sum(a == b for a, b in zip(artists, artists[1:], strict=False))
        / max(len(top) - 1, 1),
        "recently_heard_artist_share": sum(_key(a) in recent for a in artists) / len(top),
        "disliked_artist_share": sum(t.artist in listener.dislikes for t in top) / len(top),
        "constraint_violations": float(sum(not satisfies_constraints(t, session) for t in top)),
    }


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--quick", action="store_true")
    args = parser.parse_args()
    results = asyncio.run(run(quick=args.quick))
    print("HALO-BENCH SYNTHETIC catalog and listeners; not real listening data")
    versions = results["versions"]
    metrics = [m for m in next(iter(versions.values())) if not m.startswith("_")]
    print("HALO-BENCH metric " + " ".join(f"{v:>12}" for v in versions))
    for metric in metrics:
        print(f"HALO-BENCH {metric} " + " ".join(f"{versions[v][metric]:>12}" for v in versions))
    print(json.dumps(results, indent=1))


if __name__ == "__main__":
    main()
