from datetime import date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest
from fastapi.testclient import TestClient

from app.api.v1.departures import current_time
from app.main import app

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"
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
