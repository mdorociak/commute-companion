from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from app.departures import current_time
from app.gtfs.loader import load_routes, load_stations, load_trips
from app.gtfs.service_calendar import load_service_calendar
from app.gtfs.stop_times import load_stop_times
from app.main import app
from app.timetable import Timetable

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"
WARSAW = ZoneInfo("Europe/Warsaw")
BRZEG = "2246799"


def _load_timetable() -> Timetable:
    return Timetable(
        stations=load_stations(FIXTURE_DIR),
        trips=load_trips(FIXTURE_DIR),
        routes=load_routes(FIXTURE_DIR),
        service_calendar=load_service_calendar(FIXTURE_DIR),
        stop_times_by_stop=load_stop_times(FIXTURE_DIR),
    )


@pytest.fixture(autouse=True)
def reset_overrides():
    yield
    app.dependency_overrides.clear()


def _client_at(now: datetime) -> TestClient:
    app.state.timetable = _load_timetable()
    app.dependency_overrides[current_time] = lambda: now
    return TestClient(app)


def test_departures_returns_running_trains_as_json() -> None:
    client = _client_at(datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW))  
    response = client.get("/departures", params={"station_id": BRZEG})
    assert response.status_code == 200
    body = response.json()
    assert [(d["line"], d["destination"], d["platform"]) for d in body] == [
        ("D7", "Sędzisław", "II"),
        ("D1", "Wrocław Główny", "II"),
    ]


def test_departure_time_is_a_timezone_aware_iso_timestamp() -> None:
    client = _client_at(datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW))
    body = client.get("/departures", params={"station_id": BRZEG}).json()
    first = datetime.fromisoformat(body[0]["departure_time"])
    assert first == datetime(2026, 5, 20, 5, 36, tzinfo=WARSAW)


def test_unknown_station_returns_empty_list() -> None:
    client = _client_at(datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW))
    response = client.get("/departures", params={"station_id": "nope"})
    assert response.status_code == 200
    assert response.json() == []


def test_missing_station_id_is_a_validation_error() -> None:
    client = _client_at(datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW))
    response = client.get("/departures")
    assert response.status_code == 422