"""End-to-end API tests against the demo metadata provider and SQLite."""

from __future__ import annotations

import uuid
from datetime import UTC, datetime, timedelta

import httpx
import jwt

from app.services.youtube.mock import DemoMetadataProvider
from tests.conftest import AppFactory, make_settings, register


async def search_ids(client: httpx.AsyncClient, auth: dict[str, str], q: str, n: int) -> list[str]:
    response = await client.get("/api/v1/search", params={"q": q, "limit": n}, headers=auth)
    assert response.status_code == 200, response.text
    return [item["video_id"] for item in response.json()["items"]]


async def test_health(client: httpx.AsyncClient) -> None:
    response = await client.get("/health")
    assert response.status_code == 200
    body = response.json()
    assert body["status"] == "ok"
    assert body["metadata_provider"] == "demo"
    assert body["ai_planner"] == "heuristic"
    assert response.headers["X-Content-Type-Options"] == "nosniff"


# --- Authentication & authorization --------------------------------------------------


async def test_user_data_requires_auth(client: httpx.AsyncClient) -> None:
    for method, path in [("GET", "/api/v1/playlists"), ("GET", "/api/v1/preferences"),
                         ("GET", "/api/v1/search?q=x"), ("POST", "/api/v1/ai/chat")]:
        response = await client.request(method, path, json={"message": "x"})
        assert response.status_code == 401, path
        assert response.json()["error"]["code"] == "unauthenticated"


async def test_invalid_and_expired_tokens(client: httpx.AsyncClient) -> None:
    bad = await client.get("/api/v1/playlists", headers={"Authorization": "Bearer nope"})
    assert bad.json()["error"]["code"] == "invalid_token"
    expired = jwt.encode(
        {"sub": str(uuid.uuid4()), "iss": "muse-api", "typ": "access",
         "exp": int((datetime.now(UTC) - timedelta(minutes=1)).timestamp())},
        "test-secret-0123456789-0123456789-abcdef",
        algorithm="HS256",
    )
    response = await client.get("/api/v1/playlists", headers={"Authorization": f"Bearer {expired}"})
    assert response.status_code == 401
    assert response.json()["error"]["code"] == "token_expired"
    forged = jwt.encode(
        {"sub": str(uuid.uuid4()), "iss": "muse-api", "typ": "access",
         "exp": int((datetime.now(UTC) + timedelta(days=1)).timestamp())},
        "attacker-secret-attacker-secret-attacker",
        algorithm="HS256",
    )
    response = await client.get("/api/v1/playlists", headers={"Authorization": f"Bearer {forged}"})
    assert response.json()["error"]["code"] == "invalid_token"


async def test_playlists_are_isolated_between_users(
    client: httpx.AsyncClient, auth: dict[str, str]
) -> None:
    other = await register(client)
    created = await client.post("/api/v1/playlists", json={"name": "Mine"}, headers=auth)
    playlist_id = created.json()["id"]
    for method, path, body in [
        ("GET", f"/api/v1/playlists/{playlist_id}", None),
        ("PATCH", f"/api/v1/playlists/{playlist_id}", {"name": "stolen"}),
        ("DELETE", f"/api/v1/playlists/{playlist_id}", None),
        ("POST", f"/api/v1/playlists/{playlist_id}/items", {"video_id": "dQw4w9WgXcQ"}),
    ]:
        response = await client.request(method, path, json=body, headers=other)
        assert response.status_code == 404, (method, path)
    listing = await client.get("/api/v1/playlists", headers=other)
    assert listing.json()["total"] == 0
    still = await client.get(f"/api/v1/playlists/{playlist_id}", headers=auth)
    assert still.json()["name"] == "Mine"


# --- Search ---------------------------------------------------------------------------


async def test_search_with_pagination_and_attribution(
    client: httpx.AsyncClient, auth: dict[str, str]
) -> None:
    first = await client.get(
        "/api/v1/search", params={"q": "telugu melody", "limit": 5}, headers=auth
    )
    body = first.json()
    assert first.status_code == 200
    assert len(body["items"]) == 5
    assert body["provider"] == "demo"
    assert all(i["attribution"]["provider"] == "demo" for i in body["items"])
    assert body["next_page_token"]
    second = await client.get(
        "/api/v1/search",
        params={"q": "telugu melody", "limit": 5, "page_token": body["next_page_token"]},
        headers=auth,
    )
    ids_one = {i["video_id"] for i in body["items"]}
    ids_two = {i["video_id"] for i in second.json()["items"]}
    assert ids_one.isdisjoint(ids_two)


async def test_search_validation_and_empty_results(
    client: httpx.AsyncClient, auth: dict[str, str]
) -> None:
    response = await client.get("/api/v1/search", params={"q": ""}, headers=auth)
    assert response.status_code == 422
    assert response.json()["error"]["code"] == "validation_error"
    response = await client.get("/api/v1/search", params={"q": "zzzqqqxxx"}, headers=auth)
    assert response.status_code == 200
    assert response.json()["items"] == []
    response = await client.get(
        "/api/v1/search", params={"q": "x", "kind": "podcast"}, headers=auth
    )
    assert response.status_code == 422


async def test_search_history_and_suggestions(
    client: httpx.AsyncClient, auth: dict[str, str]
) -> None:
    await client.get("/api/v1/search", params={"q": "tamil kuthu beats"}, headers=auth)
    history = await client.get("/api/v1/history/search", headers=auth)
    assert [h["query"] for h in history.json()] == ["tamil kuthu beats"]
    suggestions = await client.get("/api/v1/search/suggestions", params={"q": "tam"}, headers=auth)
    assert suggestions.json()["suggestions"][0] == "tamil kuthu beats"
    cleared = await client.delete("/api/v1/history/search", headers=auth)
    assert cleared.status_code == 204
    assert (await client.get("/api/v1/history/search", headers=auth)).json() == []


async def test_video_details(client: httpx.AsyncClient, auth: dict[str, str]) -> None:
    [video_id] = await search_ids(client, auth, "korean dance", 1)
    response = await client.get(f"/api/v1/videos/{video_id}", headers=auth)
    assert response.status_code == 200
    assert response.json()["video_id"] == video_id
    missing = await client.get("/api/v1/videos/AAAAAAAAAAA", headers=auth)
    assert missing.status_code == 404
    assert missing.json()["error"]["code"] == "video_unavailable"
    invalid = await client.get("/api/v1/videos/bad!id", headers=auth)
    assert invalid.status_code == 422


class QuotaProvider(DemoMetadataProvider):
    async def search(self, query, *, page_token=None, max_results=20):  # type: ignore[no-untyped-def]
        from app.services.youtube.base import QuotaExceededError

        raise QuotaExceededError("quota")


async def test_provider_errors_are_structured(app_factory: AppFactory) -> None:
    _, client = await app_factory(provider=QuotaProvider())
    async with client:
        auth = await register(client)
        response = await client.get("/api/v1/search", params={"q": "x"}, headers=auth)
    assert response.status_code == 503
    assert response.json()["error"]["code"] == "search_quota_exceeded"
    assert response.headers["Retry-After"] == "3600"
    assert "request_id" in response.json()["error"]


# --- Rate limiting --------------------------------------------------------------------


async def test_rate_limit_search(app_factory: AppFactory) -> None:
    _, client = await app_factory(settings=make_settings(rate_limit_search_per_minute=3))
    async with client:
        auth = await register(client)
        codes = [
            (await client.get("/api/v1/search", params={"q": "pop"}, headers=auth)).status_code
            for _ in range(5)
        ]
        other = await register(client)
        other_code = (
            await client.get("/api/v1/search", params={"q": "pop"}, headers=other)
        ).status_code
    assert codes == [200, 200, 200, 429, 429]
    assert other_code == 200  # limits are per user


async def test_rate_limit_registration_by_ip(app_factory: AppFactory) -> None:
    _, client = await app_factory(settings=make_settings(rate_limit_auth_per_minute=2))
    async with client:
        codes = [(await client.post("/api/v1/auth/register", json={})).status_code
                 for _ in range(3)]
        last = await client.post("/api/v1/auth/register", json={})
    assert codes == [201, 201, 429]
    assert last.json()["error"]["code"] == "rate_limited"
    assert int(last.headers["Retry-After"]) > 0


# --- Playlists ------------------------------------------------------------------------


async def test_playlist_crud_and_ordering(client: httpx.AsyncClient, auth: dict[str, str]) -> None:
    ids = await search_ids(client, auth, "hindi love song", 4)
    created = await client.post(
        "/api/v1/playlists",
        json={"name": "  Late   Night ", "mood": "romantic", "video_ids": ids[:3]},
        headers=auth,
    )
    assert created.status_code == 201, created.text
    playlist = created.json()
    assert playlist["name"] == "Late Night"
    assert [i["video_id"] for i in playlist["items"]] == ids[:3]
    assert [i["position"] for i in playlist["items"]] == [0, 1, 2]
    assert playlist["item_count"] == 3
    assert playlist["total_duration_seconds"] > 0
    pid = playlist["id"]

    added = await client.post(
        f"/api/v1/playlists/{pid}/items", json={"video_id": ids[3], "position": 1}, headers=auth
    )
    assert added.status_code == 201
    assert [i["video_id"] for i in added.json()["items"]] == [ids[0], ids[3], ids[1], ids[2]]

    items = added.json()["items"]
    reversed_ids = [i["id"] for i in reversed(items)]
    reordered = await client.put(
        f"/api/v1/playlists/{pid}/items/order", json={"item_ids": reversed_ids}, headers=auth
    )
    assert reordered.status_code == 200
    assert [i["id"] for i in reordered.json()["items"]] == reversed_ids

    bad_order = await client.put(
        f"/api/v1/playlists/{pid}/items/order", json={"item_ids": reversed_ids[:2]}, headers=auth
    )
    assert bad_order.status_code == 422
    assert bad_order.json()["error"]["code"] == "invalid_reorder"

    removed = await client.delete(f"/api/v1/playlists/{pid}/items/{reversed_ids[0]}", headers=auth)
    assert removed.status_code == 200
    remaining = removed.json()["items"]
    assert [i["position"] for i in remaining] == [0, 1, 2]
    assert reversed_ids[0] not in {i["id"] for i in remaining}

    # Persisted across requests
    fetched = await client.get(f"/api/v1/playlists/{pid}", headers=auth)
    assert [i["id"] for i in fetched.json()["items"]] == [i["id"] for i in remaining]

    renamed = await client.patch(
        f"/api/v1/playlists/{pid}",
        json={"name": "Renamed", "youtube_playlist_id": "PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"},
        headers=auth,
    )
    assert renamed.json()["name"] == "Renamed"
    assert renamed.json()["youtube_playlist_url"] == (
        "https://www.youtube.com/playlist?list=PLrAXtmErZgOeiKm4sgNOknGvNjby9efdf"
    )

    deleted = await client.delete(f"/api/v1/playlists/{pid}", headers=auth)
    assert deleted.status_code == 204
    assert (await client.get(f"/api/v1/playlists/{pid}", headers=auth)).status_code == 404


async def test_playlist_rejects_unverified_and_malformed_ids(
    client: httpx.AsyncClient, auth: dict[str, str]
) -> None:
    fabricated = await client.post(
        "/api/v1/playlists", json={"name": "x", "video_ids": ["AAAAAAAAAAA"]}, headers=auth
    )
    assert fabricated.status_code == 422
    assert fabricated.json()["error"]["code"] == "video_unavailable"
    malformed = await client.post(
        "/api/v1/playlists", json={"name": "x", "video_ids": ["javascript:1"]}, headers=auth
    )
    assert malformed.status_code == 422
    bad_playlist = await client.post(
        "/api/v1/playlists", json={"name": "x", "youtube_playlist_id": "evil&list"}, headers=auth
    )
    assert bad_playlist.status_code == 422
    blank = await client.post("/api/v1/playlists", json={"name": "   "}, headers=auth)
    assert blank.status_code == 422


async def test_playlist_pagination(client: httpx.AsyncClient, auth: dict[str, str]) -> None:
    for index in range(5):
        await client.post("/api/v1/playlists", json={"name": f"P{index}"}, headers=auth)
    page = await client.get("/api/v1/playlists", params={"limit": 2, "offset": 2}, headers=auth)
    body = page.json()
    assert body["total"] == 5 and len(body["items"]) == 2


# --- Preferences, taste, privacy ----------------------------------------------------


PREFS = {
    "personalization_enabled": True,
    "store_ai_conversations": True,
    "languages": ["Telugu", "telugu", "Hindi"],
    "genres": ["melody"],
    "moods": ["calm"],
    "discovery_preference": "discovery",
    "favorite_artists": [{"name": "Aarav Strings"}, {"name": "Velvet Atlas"}],
    "excluded_artists": [{"name": "Velvet Atlas"}, {"name": "Northern Static"}],
    "onboarding_completed": True,
}


async def test_preferences_roundtrip(client: httpx.AsyncClient, auth: dict[str, str]) -> None:
    default = await client.get("/api/v1/preferences", headers=auth)
    assert default.json()["personalization_enabled"] is False
    saved = await client.put("/api/v1/preferences", json=PREFS, headers=auth)
    body = saved.json()
    assert saved.status_code == 200
    assert body["languages"] == ["Telugu", "Hindi"]
    assert body["personalization_consent_at"] is not None
    # Exclusion wins over favorite for the same artist
    assert [a["name"] for a in body["favorite_artists"]] == ["Aarav Strings"]
    assert {a["name"] for a in body["excluded_artists"]} == {"Velvet Atlas", "Northern Static"}
    off = await client.put(
        "/api/v1/preferences",
        json={**PREFS, "personalization_enabled": False},
        headers=auth,
    )
    assert off.json()["store_ai_conversations"] is False  # requires consent
    assert off.json()["personalization_consent_at"] is None


async def test_taste_profile_and_reset(client: httpx.AsyncClient, auth: dict[str, str]) -> None:
    await client.put("/api/v1/preferences", json=PREFS, headers=auth)
    ids = await search_ids(client, auth, "telugu melody", 2)
    await client.post("/api/v1/playlists", json={"name": "t", "video_ids": ids}, headers=auth)
    await client.post(
        "/api/v1/recommendations/feedback",
        json={"video_id": ids[0], "rating": "like", "channel_title": "Aarav Strings"},
        headers=auth,
    )
    taste = (await client.get("/api/v1/preferences/taste", headers=auth)).json()
    assert "cannot see what you play in Brave" in taste["basis"]
    assert taste["activity_counts"]["feedback"] == 1
    assert taste["activity_counts"]["searches"] == 1
    assert any(s["label"] == "Aarav Strings" for s in taste["top_artists"])
    reset = await client.delete("/api/v1/preferences/taste", headers=auth)
    assert reset.status_code == 204
    after = (await client.get("/api/v1/preferences/taste", headers=auth)).json()
    assert after["activity_counts"]["feedback"] == 0
    assert after["activity_counts"]["searches"] == 0
    assert after["activity_counts"]["playlists"] == 1  # saved playlists are kept


async def test_feedback_not_stored_without_consent(
    client: httpx.AsyncClient, auth: dict[str, str]
) -> None:
    [video_id] = await search_ids(client, auth, "lofi", 1)
    response = await client.post(
        "/api/v1/recommendations/feedback",
        json={"video_id": video_id, "rating": "dislike"},
        headers=auth,
    )
    assert response.json()["recorded"] is False
    invalid = await client.post(
        "/api/v1/recommendations/feedback",
        json={"video_id": video_id, "rating": "meh"},
        headers=auth,
    )
    assert invalid.status_code == 422


async def test_export_and_delete_account(client: httpx.AsyncClient, auth: dict[str, str]) -> None:
    await client.put("/api/v1/preferences", json=PREFS, headers=auth)
    ids = await search_ids(client, auth, "spanish", 2)
    await client.post("/api/v1/playlists", json={"name": "Export me", "video_ids": ids},
                      headers=auth)
    export = await client.get("/api/v1/me/export", headers=auth)
    data = export.json()
    assert data["playlists"][0]["name"] == "Export me"
    assert data["preferences"]["languages"] == ["Telugu", "Hindi"]
    deleted = await client.delete("/api/v1/me", headers=auth)
    assert deleted.status_code == 204
    after = await client.get("/api/v1/playlists", headers=auth)
    assert after.status_code == 401
    assert after.json()["error"]["code"] == "account_deleted"


async def test_validation_errors_do_not_echo_input(
    client: httpx.AsyncClient, auth: dict[str, str]
) -> None:
    secret_text = "my very private feelings " * 100
    response = await client.post("/api/v1/ai/chat", json={"message": secret_text}, headers=auth)
    assert response.status_code == 422
    assert "private feelings" not in response.text
