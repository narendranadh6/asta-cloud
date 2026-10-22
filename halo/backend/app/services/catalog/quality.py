"""Keeping Halo's catalog legal: spotting likely unauthorised re-uploads.

Open platforms like Audius let anyone upload. Most uploads are artists sharing their own
work, but some accounts post rips of commercial songs (often film music) taken from download
sites or video platforms. Halo only wants music the uploader has the right to share, so tracks
that carry the usual traces of a rip are left out. This is a conservative heuristic, tuned on
the Halo Drive catalog audit; it errs toward dropping a doubtful track.
"""

from __future__ import annotations

import re

# Names of download/rip sites and converter tools that end up in re-uploaded titles.
_RIP_SITES = (
    "y2mate",
    "sensongs",
    "naasongs",
    "naa songs",
    "masstamilan",
    "pagalworld",
    "djmaza",
    "mrjatt",
    "mr-jatt",
    "songspk",
    "songs.pk",
    "bdmuzik",
    "starmusiq",
    "isaimini",
    "tamilwire",
    "atozmp3",
    "wapking",
    "djpunjab",
    "pendujatt",
    "savefrom",
    "ytmp3",
    "mp3juices",
    "ssyoutube",
    "teluguwap",
    "tollywoodmp3",
    "sensongsmp3",
)

# Phrases that describe a video or a download rather than a song released by its artist.
_RIP_PHRASES = (
    "full video song",
    "video song",
    "lyric video",
    "lyrical video",
    "official video",
    "official music video",
    "official audio",
    "audio jukebox",
    "jukebox",
    "ringtone",
    "whatsapp status",
    "status video",
    "full song",
    "hd video",
    "4k video",
    "movie climax",
    "full movie",
    "bgm ringtone",
    "kbps",
    "320k",
    "128k",
    "mp3",
)

# Web addresses in a title ("Song-SenSongsMp3.Co") are a strong sign of a rip.
_DOMAIN = re.compile(r"\b[\w-]+\.(?:com|co|net|in|org|me|cc|info|io|pk|bd)\b", re.IGNORECASE)

# Accounts named after a language or film industry ("Telugu Music", "Melodious Mana Telugu")
# are typically re-upload channels; artists rarely name themselves after one.
_CHANNEL = re.compile(
    r"\b(?:telugu|tamil|hindi|bollywood|tollywood|kollywood|malayalam|kannada|punjabi)\b",
    re.IGNORECASE,
)


def looks_like_reupload(title: str, artist: str = "", tags: str = "") -> bool:
    """True when a track shows the usual traces of an unauthorised rip."""
    text = f"{title} {tags}".lower()
    if any(site in text or site in artist.lower() for site in _RIP_SITES):
        return True
    if any(phrase in text for phrase in _RIP_PHRASES):
        return True
    if _DOMAIN.search(title) or _DOMAIN.search(artist):
        return True
    return bool(_CHANNEL.search(artist))
