# Commuter Backend

FastAPI service that loads static GTFS from Koleje Dolnośląskie (KD), interprets
it against the GTFS service calendar, and exposes a versioned REST API consumed
by the iOS app.

GTFS-Realtime parsing exists in `src/app/gtfs_rt/` but is not integrated into
departure responses. MPK Wrocław integration, connection calculation, feed
refresh, and freshness metadata are planned, not built.

## Prerequisites

- Python 3.11+
- [uv](https://docs.astral.sh/uv/) for dependency and environment management

## Setup

```bash
cd backend
uv sync
```

This creates `.venv/` and installs both runtime and dev dependencies from the lockfile.

## Run the server

```bash
uv run uvicorn app.main:app --reload
```

Then open <http://127.0.0.1:8000/health> — you should see `{"status":"ok"}`. Interactive docs are at <http://127.0.0.1:8000/docs>.

The initial public API routes are:

- `GET /api/v1/stations`
- `GET /api/v1/stations/{station_id}/departures`

`GET /api/v1/stations` returns every station in one response. The iOS client
fetches the list once and filters it locally, so there is no server-side
search parameter.

The health route remains unversioned because it describes the service rather than a product resource.

## Run tests

```bash
uv run pytest
```
