# Commuter Backend

FastAPI service that parses GTFS (static and real-time) from Koleje Dolnośląskie and MPK Wrocław, normalizes the data, and exposes a REST API consumed by the iOS app.

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

## Run tests

```bash
uv run pytest
```
