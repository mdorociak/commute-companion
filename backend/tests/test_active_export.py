import json
import logging
from collections.abc import Callable
from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from app.api.v1.departures import current_time
from app.main import app

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"
CONTRACT_DIR = Path(__file__).parents[2] / "contract"
WARSAW = ZoneInfo("Europe/Warsaw")
BRZEG = "2246799"

FIXTURE_BOARD = [
    ("D7", "2026-05-20T05:36:00+02:00"),
    ("D1", "2026-05-20T14:32:00+02:00"),
]
FIXTURE_STATIONS = ["Brzeg", "Brzeg Dolny", "Empty Station", "Oława"]

RENAMED_STATION = ("Brzeg Dolny", "Brzeg Dolny Wschodni")
LATER_FEED_END = ("20261212", "20261213")
D7_AT_BRZEG = "38645733_409036,05:36:00,05:36:00"


@pytest.fixture(autouse=True)
def serve_the_fixture_export(monkeypatch: pytest.MonkeyPatch):
    monkeypatch.setenv("KD_GTFS_DIR", str(FIXTURE_DIR))
    app.dependency_overrides[current_time] = lambda: datetime(
        2026, 5, 20, 5, 0, tzinfo=WARSAW
    )
    yield
    app.dependency_overrides.clear()


def _export(tmp_path: Path, replacements: dict[str, tuple[str, str]]) -> Path:
    export_dir = tmp_path / "export"
    export_dir.mkdir()
    for source in FIXTURE_DIR.glob("*.txt"):
        text = source.read_text(encoding="utf-8")
        if source.name in replacements:
            old, new = replacements[source.name]
            assert old in text
            text = text.replace(old, new)
        (export_dir / source.name).write_text(text, encoding="utf-8")
    return export_dir


def _board(client: TestClient) -> list[tuple[str, str]]:
    response = client.get(f"/api/v1/stations/{BRZEG}/departures")
    assert response.status_code == 200
    return [
        (departure["line"], departure["departure_time"])
        for departure in response.json()
    ]


def _station_names(client: TestClient) -> list[str]:
    response = client.get("/api/v1/stations")
    assert response.status_code == 200
    return [station["name"] for station in response.json()]


def _contract_response(route: str, name: str) -> dict[str, object]:
    path = CONTRACT_DIR / route / f"{name}.json"
    return json.loads(path.read_text(encoding="utf-8"))


def _only_stops(tmp_path: Path) -> Path:
    export_dir = _export(tmp_path, {})
    for path in export_dir.glob("*.txt"):
        if path.name != "stops.txt":
            path.unlink()
    return export_dir


def _without_the_stop_id_column(tmp_path: Path) -> Path:
    return _export(tmp_path, {"stops.txt": ("stop_id,stop_code", "stopid,stop_code")})


def _with_a_malformed_time(tmp_path: Path) -> Path:
    return _export(
        tmp_path,
        {"stop_times.txt": (D7_AT_BRZEG, "38645733_409036,05:xx:00,05:xx:00")},
    )


def _header_only(tmp_path: Path, file_name: str) -> Path:
    export_dir = _export(tmp_path, {})
    path = export_dir / file_name
    header = path.read_text(encoding="utf-8").splitlines()[0]
    path.write_text(header + "\n", encoding="utf-8")
    return export_dir


def test_after_a_swap_departures_stations_and_feed_info_come_from_the_new_export(
    tmp_path: Path,
) -> None:
    newer = _export(
        tmp_path,
        {
            "stops.txt": RENAMED_STATION,
            "feed_info.txt": LATER_FEED_END,
            "stop_times.txt": (D7_AT_BRZEG, "38645733_409036,05:41:00,05:41:00"),
        },
    )

    with TestClient(app) as client:
        board_before = _board(client)
        stations_before = _station_names(client)
        app.state.active_export.install(newer)
        board_after = _board(client)
        stations_after = _station_names(client)
        feed_info_after = app.state.active_export.current.feed_info

    assert board_before == FIXTURE_BOARD
    assert stations_before == FIXTURE_STATIONS
    assert board_after == [
        ("D7", "2026-05-20T05:41:00+02:00"),
        ("D1", "2026-05-20T14:32:00+02:00"),
    ]
    assert stations_after == ["Brzeg", "Brzeg Dolny Wschodni", "Empty Station", "Oława"]
    assert feed_info_after is not None
    assert feed_info_after.end_date == date(2026, 12, 13)


def test_a_build_that_fails_after_loading_stations_leaves_the_previous_export_serving(
    tmp_path: Path,
) -> None:
    broken = _export(
        tmp_path,
        {
            "stops.txt": RENAMED_STATION,
            "feed_info.txt": LATER_FEED_END,
            "stop_times.txt": (D7_AT_BRZEG, "38645733_409036,05:xx:00,05:xx:00"),
        },
    )

    with TestClient(app) as client:
        feed_info_before = app.state.active_export.current.feed_info
        with pytest.raises(ValueError):
            app.state.active_export.install(broken)
        board_after = _board(client)
        stations_after = _station_names(client)
        feed_info_after = app.state.active_export.current.feed_info

    assert board_after == FIXTURE_BOARD
    assert stations_after == FIXTURE_STATIONS
    assert feed_info_after == feed_info_before
    assert feed_info_after is not None
    assert feed_info_after.end_date == date(2026, 12, 12)


def test_with_no_export_both_routes_answer_timetable_unavailable_and_health_stays_ok(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("KD_GTFS_DIR", str(tmp_path))

    with TestClient(app) as client:
        departures = client.get(f"/api/v1/stations/{BRZEG}/departures")
        stations = client.get("/api/v1/stations")
        health = client.get("/health")

    departures_contract = _contract_response("departures", "timetable_unavailable")
    stations_contract = _contract_response("stations", "timetable_unavailable")
    assert departures.status_code == departures_contract["status"]
    assert departures.json() == departures_contract["body"]
    assert stations.status_code == stations_contract["status"]
    assert stations.json() == stations_contract["body"]
    assert health.status_code == 200
    assert health.json() == {"status": "ok"}


@pytest.mark.parametrize(
    "damaged_export",
    [_only_stops, _without_the_stop_id_column, _with_a_malformed_time],
    ids=["only_stops_txt", "missing_stop_id_column", "malformed_time"],
)
def test_an_export_that_fails_to_build_at_startup_leaves_the_server_unavailable(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    caplog: pytest.LogCaptureFixture,
    damaged_export: Callable[[Path], Path],
) -> None:
    export_dir = damaged_export(tmp_path)
    monkeypatch.setenv("KD_GTFS_DIR", str(export_dir))

    with TestClient(app) as client:
        response = client.get(f"/api/v1/stations/{BRZEG}/departures")

    assert response.status_code == 503
    assert response.json() == {"code": "timetable_unavailable"}
    errors = [record for record in caplog.records if record.levelno == logging.ERROR]
    assert len(errors) == 1
    assert str(export_dir) in errors[0].getMessage()


@pytest.mark.parametrize("file_name", ["stops.txt", "trips.txt", "stop_times.txt"])
def test_an_export_without_stations_trips_or_stop_times_is_not_installed_at_startup(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
    file_name: str,
) -> None:
    monkeypatch.setenv("KD_GTFS_DIR", str(_header_only(tmp_path, file_name)))

    with TestClient(app) as client:
        response = client.get("/api/v1/stations")

    assert response.status_code == 503
    assert response.json() == {"code": "timetable_unavailable"}


def test_the_first_install_after_starting_with_no_export_serves_that_export(
    tmp_path: Path,
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.setenv("KD_GTFS_DIR", str(tmp_path))

    with TestClient(app) as client:
        before = client.get("/api/v1/stations")
        app.state.active_export.install(FIXTURE_DIR)
        board_after = _board(client)
        stations_after = _station_names(client)

    assert before.status_code == 503
    assert board_after == FIXTURE_BOARD
    assert stations_after == FIXTURE_STATIONS
