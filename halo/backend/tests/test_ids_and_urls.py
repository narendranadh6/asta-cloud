import pytest

from app.services.youtube.ids import (
    extract_video_id,
    is_valid_playlist_id,
    is_valid_video_id,
    playlist_url,
    watch_url,
)


@pytest.mark.parametrize("value", ["dQw4w9WgXcQ", "abc-DEF_123", "___________"])
def test_valid_video_ids(value: str) -> None:
    assert is_valid_video_id(value)


@pytest.mark.parametrize(
    "value",
    ["", "short", "dQw4w9WgXcQQ", "dQw4w9WgXc!", "dQw4w9WgXc ", "../../etc/pa", None, 12345678901,
     "dQw4w9WgX&c", "dQw4w9%67Xc"],
)
def test_invalid_video_ids(value: object) -> None:
    assert not is_valid_video_id(value)


def test_watch_url_is_canonical_and_rejects_bad_ids() -> None:
    assert watch_url("dQw4w9WgXcQ") == "https://www.youtube.com/watch?v=dQw4w9WgXcQ"
    with pytest.raises(ValueError):
        watch_url("bad&id=evil")


def test_playlist_ids() -> None:
    assert is_valid_playlist_id("PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf")
    assert is_valid_playlist_id("OLAK5uy_kq5dpzbd1yBpVq5YlXP7sOq3g6mXf8dvY")
    assert not is_valid_playlist_id("XX123")
    assert not is_valid_playlist_id("PL<script>alert(1)</script>")
    assert playlist_url("PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf").endswith(
        "playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"
    )


@pytest.mark.parametrize(
    ("url", "expected"),
    [
        ("https://www.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://m.youtube.com/watch?v=dQw4w9WgXcQ&list=PL123", "dQw4w9WgXcQ"),
        ("https://youtu.be/dQw4w9WgXcQ?t=10", "dQw4w9WgXcQ"),
        ("https://www.youtube.com/shorts/dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://music.youtube.com/watch?v=dQw4w9WgXcQ", "dQw4w9WgXcQ"),
        ("https://evil.example/watch?v=dQw4w9WgXcQ", None),
        ("https://youtube.com.evil.example/watch?v=dQw4w9WgXcQ", None),
        ("javascript:alert(1)//youtube.com/watch?v=dQw4w9WgXcQ", None),
        ("https://www.youtube.com/watch?v=tooShort", None),
        ("not a url", None),
    ],
)
def test_extract_video_id(url: str, expected: str | None) -> None:
    assert extract_video_id(url) == expected
