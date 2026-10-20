# Setup, credentials & deployment

## 1. Backend (local)

Requirements: Docker, or Python 3.12 + PostgreSQL 16 + Redis 7.

```bash
cd halo
cp .env.example .env           # fill in what you have; everything is optional locally
docker compose up --build      # API on http://localhost:8000, runs migrations on start
curl localhost:8000/health
```

Without Docker:

```bash
cd halo/backend
python3.12 -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"
export HALO_DATABASE_URL=postgresql+asyncpg://halo:halo@localhost:5432/halo
alembic upgrade head
uvicorn app.main:app --reload
```

### Tests

```bash
cd halo/backend
pytest -q                                   # SQLite, no services needed
HALO_TEST_DATABASE_URL=postgresql+asyncpg://halo:halo@localhost:5432/halo_test pytest -q
ruff check app tests alembic && mypy app
```

## 2. Credentials

| Variable | Needed for | How to get it |
|---|---|---|
| `HALO_JWT_SECRET` | Production auth (32+ chars) | `python -c "import secrets; print(secrets.token_urlsafe(48))"` |
| `HALO_YOUTUBE_API_KEY` | Music search (required) | Google Cloud Console → enable *YouTube Data API v3* → Credentials → API key. Restrict it to that API and to your server's IPs |
| `HALO_LASTFM_API_KEY` | Optional: similar artists for recommendations | https://www.last.fm/api/account/create (free). Deezer related artists work without a key (`HALO_DEEZER_ENABLED=true`) |
| `HALO_RADIO_BROWSER_BASE_URL` | Optional: live radio directory mirror | Defaults to `https://de1.api.radio-browser.info` |
| `HALO_LLM_PROVIDER` / `HALO_LLM_API_KEY` / `HALO_LLM_MODEL` | Optional AI planner | `anthropic` (default model `claude-sonnet-5-5`) or `openai` (any OpenAI-compatible `/chat/completions`, set `HALO_LLM_BASE_URL` if needed) |

Without a YouTube key the API still starts, but search endpoints return
`503 search_misconfigured` and the app shows a setup notice. Without an LLM key the
deterministic planner is used.

Never commit `.env`. In production, inject secrets from your platform's secret manager.

## 3. iOS app

Requirements: macOS with Xcode 16+ (Swift 6, iOS 17 SDK).

```bash
cd halo/ios
open Halo.xcodeproj               # pre-generated; or regenerate:
brew install xcodegen && xcodegen generate
```

* Debug points at `http://localhost:8000` (`Config/Debug.xcconfig`). On a **physical
  iPhone**, change it to your Mac's LAN IP, e.g. `http:/$()/192.168.1.20:8000`.
  `NSAllowsLocalNetworking` permits plain HTTP only for local addresses.
* Release points at `https://api.halo.example` (`Config/Release.xcconfig`). Replace it with
  your HTTPS domain.
* Launch argument `-HaloInMemoryStore` gives a throwaway SwiftData store. `HALO_API_BASE_URL` in
  the scheme environment points a debug build at another server.
* Set `DEVELOPMENT_TEAM` in `project.yml` (or in Xcode) for device builds.

Tests:

```bash
cd halo/ios
swift test                        # core + view models, works on macOS or Linux
xcodebuild test -project Halo.xcodeproj -scheme Halo \
  -destination 'platform=iOS Simulator,name=iPhone 16'   # adds SwiftData tests
```

Then run the real-device checklist in [brave-integration.md](brave-integration.md).

## 4. Deployment

* Build `halo/backend/Dockerfile`. The container runs `alembic upgrade head` and then
  uvicorn on port 8000 as a non-root user.
* Put it behind TLS (load balancer, Fly.io, Cloud Run, ECS and so on). Set
  `HALO_ENVIRONMENT=production`. The app refuses to start without a strong `HALO_JWT_SECRET`,
  and without `HALO_YOUTUBE_API_KEY`. `/docs` is disabled in production.
* Managed PostgreSQL and Redis: set `HALO_DATABASE_URL` and `HALO_REDIS_URL`.
* Schedule `python -m app.tasks.refresh_metadata` daily (YouTube 30-day storage rule) and
  `python -m app.tasks.train_ranker` daily or weekly (retrains the ranker from feedback).
* Run more than one replica only with Redis configured, so rate limits are shared.

## 5. TestFlight preparation

1. Set the bundle id, team and the production `HALO_API_BASE_URL`.
2. Add a 1024×1024 app icon to `Assets.xcassets/AppIcon.appiconset`.
3. Bump `MARKETING_VERSION` and `CURRENT_PROJECT_VERSION`.
4. Product → Archive → Distribute → TestFlight.
5. App Privacy answers should match `PrivacyInfo.xcprivacy`: user ID, search history and
   user content, linked, used for app functionality and personalization, **not** used for
   tracking.
6. App Review notes: explain that playback opens in the user's browser, that Halo uses the
   YouTube Data API for metadata only, and that it doesn't download or modify content.
7. Complete the Brave real-device checklist on at least one device before external testing.
