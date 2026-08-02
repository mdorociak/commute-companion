from fastapi.testclient import TestClient

from app.gtfs.models import Platform, Station
from app.main import app


def _stub_state() -> dict[str, Station]:
    return {
        "2246799": Station(
            id="2246799", name="Brzeg", code="11",
            lat=50.852881, lon=17.470911,
            platforms=[Platform(id="2333170", code="II")],
        ),
        "1413092": Station(
            id="1413092", name="Brzeg Dolny", code="12",
            lat=51.266894, lon=16.725, platforms=[],
        ),
        "0000001": Station(
            id="0000001", name="Wrocław Główny", code="WRO",
            lat=51.098, lon=17.036, platforms=[],
        ),
    }


def test_stations_endpoint_returns_all_stations_sorted_by_name() -> None:
    app.state.stations = _stub_state()
    client = TestClient(app)
    response = client.get("/api/v1/stations")
    assert response.status_code == 200
    names = [s["name"] for s in response.json()]
    assert names == ["Brzeg", "Brzeg Dolny", "Wrocław Główny"]


def test_stations_search_matches_substring_case_insensitively() -> None:
    app.state.stations = _stub_state()
    client = TestClient(app)
    response = client.get("/api/v1/stations?search=brzeg")
    assert response.status_code == 200
    names = [s["name"] for s in response.json()]
    assert names == ["Brzeg", "Brzeg Dolny"]


def test_stations_search_with_no_matches_returns_empty_list() -> None:
    app.state.stations = _stub_state()
    client = TestClient(app)
    response = client.get("/api/v1/stations?search=nonexistent")
    assert response.status_code == 200
    assert response.json() == []


def test_stations_response_includes_platforms() -> None:
    app.state.stations = _stub_state()
    client = TestClient(app)
    response = client.get("/api/v1/stations?search=brzeg dolny")
    body = response.json()
    assert len(body) == 1
    brzeg = body[0]
    assert "platforms" in brzeg
    assert brzeg["platforms"] == []


def test_unversioned_stops_route_is_not_exposed() -> None:
    app.state.stations = _stub_state()
    response = TestClient(app).get("/stops")
    assert response.status_code == 404
