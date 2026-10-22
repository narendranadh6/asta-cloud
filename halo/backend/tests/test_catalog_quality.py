"""Re-upload filtering and feature estimates (Halo Drive phase 1)."""

from __future__ import annotations

import pytest

from app.services.catalog.features import estimate, language_hint
from app.services.catalog.quality import looks_like_reupload


@pytest.mark.parametrize(
    ("title", "artist"),
    [
        # Real titles from the catalog audit.
        ("y2mate.com - Arabic Kuthu  Official Lyric Video", "Ethan Hunt"),
        ("Billa Theme Song-SenSongsMp3.Co", "Telugu Music❤️"),
        ("Hamsa Naava Full Video Song - Baahubali 2 Video Song", "leon's"),
        ("AlaVaikunthapurramuloo - ButtaBomma( 256kbps cbr )", "Jubayer"),
        ("Tu Thodi Der Aur Thehar Ja Female Version Ringtone", "Neer"),
        ("Pushpa Movie Climax ! Pushpa Movie ! Allu Arjun !", "Djrockers131"),
        ("Ala Vaikunthapurramuloo", "Melodious Mana Telugu"),
        ("Some Song", "Tamil Hits Channel"),
    ],
)
def test_rips_are_recognised(title: str, artist: str) -> None:
    assert looks_like_reupload(title, artist)


@pytest.mark.parametrize(
    ("title", "artist"),
    [
        ("Monsoon Drive", "Madras Monsoon"),
        ("Thangamey cover | tamil", "Aman"),  # covers are the uploader's own performance
        ("Telugu Tech", "Wax Motif"),
        ("Orbital Trajectory (DSP Edit)", "VEQTOR"),
        ("Neon Run (Remix)", "Dawn Circuit"),
    ],
)
def test_original_uploads_are_kept(title: str, artist: str) -> None:
    assert not looks_like_reupload(title, artist)


def test_language_comes_from_script_words_or_the_source_never_from_english_titles() -> None:
    assert language_hint("ఇదే కదా") == "te"
    assert language_hint("Margib - 2021 Telugu Vibes Mixtape") == "te"
    assert language_hint("Love Story", "Tollywood Nights") == "te"
    assert language_hint("Butterfly Effect") is None  # could be any language
    assert estimate(title="Nuvve", lang="te").language == "te"
    assert estimate(title="Night Drive", lang="en").language == "en"


def test_energy_and_tempo_estimates() -> None:
    calm = estimate(title="x", mood="Peaceful")
    loud = estimate(title="x", mood="Energizing", bpm=150)
    assert calm.energy is not None and loud.energy is not None and calm.energy < loud.energy
    assert loud.tempo == 0.75
    assert estimate(title="x", genre="Electronic").energy == 0.75
    assert estimate(title="x", speed="veryhigh").tempo == 0.9
    unknown = estimate(title="x")
    assert (unknown.language, unknown.energy, unknown.tempo) == (None, None, None)
