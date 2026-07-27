from datetime import datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from app.gtfs.loader import load_routes, load_stations, load_trips
from app.gtfs.service_calendar import load_service_calendar
from app.gtfs.stop_times import load_stop_times
from app.timetable import Timetable

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"
WARSAW = ZoneInfo("Europe/Warsaw")

BRZEG = "2246799"
BRZEG_DOLNY = "1413092"


def _timetable() -> Timetable:
    return Timetable(
        stations=load_stations(FIXTURE_DIR),
        trips=load_trips(FIXTURE_DIR),
        routes=load_routes(FIXTURE_DIR),
        service_calendar=load_service_calendar(FIXTURE_DIR),
        stop_times_by_stop=load_stop_times(FIXTURE_DIR),
    )


def test_weekday_morning_lists_running_weekday_departures() -> None:
    deps = _timetable().next_departures(BRZEG, datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW))
    assert [(d.line, d.destination) for d in deps] == [
        ("D7", "Sędzisław"),
        ("D1", "Wrocław Główny"),
    ]


def test_already_departed_trains_are_excluded() -> None:
    deps = _timetable().next_departures(BRZEG, datetime(2026, 5, 20, 10, 0, tzinfo=WARSAW))
    assert [d.line for d in deps] == ["D1"]


def test_weekend_service_and_past_midnight_absolute_time() -> None:
    deps = _timetable().next_departures(BRZEG, datetime(2026, 5, 23, 20, 0, tzinfo=WARSAW))
    assert len(deps) == 1
    departure = deps[0]
    assert departure.line == "D7"
    assert departure.destination is None 
    assert departure.departure_time == datetime(2026, 5, 24, 1, 10, tzinfo=WARSAW)


def test_platform_code_is_included() -> None:
    deps = _timetable().next_departures(BRZEG, datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW))
    assert deps[0].platform == "II"


def test_no_pickup_stops_are_excluded() -> None:
    deps = _timetable().next_departures(BRZEG_DOLNY, datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW))
    assert [d.line for d in deps] == ["D7"]


def test_unknown_station_returns_empty() -> None:
    deps = _timetable().next_departures("nonexistent", datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW))
    assert deps == []


def test_limit_caps_the_result_count() -> None:
    deps = _timetable().next_departures(
        BRZEG, datetime(2026, 5, 20, 0, 0, tzinfo=WARSAW), limit=1
    )
    assert len(deps) == 1
    assert deps[0].line == "D7"