from datetime import UTC, date, datetime
from pathlib import Path
from zoneinfo import ZoneInfo

from app.gtfs.loader import load_routes, load_stations, load_trips
from app.gtfs.models import Route, Station, Trip
from app.gtfs.service_calendar import (
    ServiceCalendar,
    ServiceException,
    load_service_calendar,
)
from app.gtfs.service_day import QueryWindow
from app.gtfs.stop_times import StopTime, load_stop_times
from app.timetable import Departure, Timetable

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
        provider_timezone=WARSAW,
    )


def _departures_between(
    station_id: str,
    start: datetime,
    end: datetime,
    limit: int = 10,
) -> list[Departure]:
    return _timetable().departures_in_window(
        station_id,
        QueryWindow(start, end),
        limit=limit,
    )


def test_weekday_morning_lists_running_weekday_departures() -> None:
    deps = _departures_between(
        BRZEG,
        datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW),
        datetime(2026, 5, 20, 16, 0, tzinfo=WARSAW),
    )
    assert [(d.line, d.destination) for d in deps] == [
        ("D7", "Sędzisław"),
        ("D1", "Wrocław Główny"),
    ]


def test_already_departed_trains_are_excluded() -> None:
    deps = _departures_between(
        BRZEG,
        datetime(2026, 5, 20, 10, 0, tzinfo=WARSAW),
        datetime(2026, 5, 20, 16, 0, tzinfo=WARSAW),
    )
    assert [d.line for d in deps] == ["D1"]


def test_weekend_service_and_past_midnight_absolute_time() -> None:
    deps = _departures_between(
        BRZEG,
        datetime(2026, 5, 23, 20, 0, tzinfo=WARSAW),
        datetime(2026, 5, 24, 2, 0, tzinfo=WARSAW),
    )
    assert len(deps) == 1
    departure = deps[0]
    assert departure.line == "D7"
    assert departure.destination is None
    assert departure.departure_time == datetime(2026, 5, 24, 1, 10, tzinfo=WARSAW)


def test_platform_code_is_included() -> None:
    deps = _departures_between(
        BRZEG,
        datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW),
        datetime(2026, 5, 20, 7, 0, tzinfo=WARSAW),
    )
    assert deps[0].platform == "II"


def test_no_pickup_stops_are_excluded() -> None:
    deps = _departures_between(
        BRZEG_DOLNY,
        datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW),
        datetime(2026, 5, 20, 16, 0, tzinfo=WARSAW),
    )
    assert [d.line for d in deps] == ["D7"]


def test_unknown_station_returns_empty() -> None:
    deps = _departures_between(
        "nonexistent",
        datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW),
        datetime(2026, 5, 20, 6, 0, tzinfo=WARSAW),
    )
    assert deps == []


def test_limit_caps_the_result_count() -> None:
    deps = _departures_between(
        BRZEG,
        datetime(2026, 5, 20, 0, 0, tzinfo=WARSAW),
        datetime(2026, 5, 20, 16, 0, tzinfo=WARSAW),
        limit=1,
    )
    assert len(deps) == 1
    assert deps[0].line == "D7"


def test_previous_service_day_departure_is_returned_after_midnight() -> None:
    deps = _timetable().departures_in_window(
        BRZEG,
        QueryWindow(
            datetime(2026, 5, 24, 0, 30, tzinfo=WARSAW),
            datetime(2026, 5, 24, 2, 0, tzinfo=WARSAW),
        ),
    )

    expected = datetime(2026, 5, 24, 1, 10, tzinfo=WARSAW)

    assert ("D7", expected) in [
        (departure.line, departure.departure_time)
        for departure in deps
    ]


def test_previous_service_day_calendar_is_evaluated_for_saturday() -> None:
    timetable = _timetable()
    window = QueryWindow(
        datetime(2026, 5, 24, 0, 30, tzinfo=WARSAW),
        datetime(2026, 5, 24, 2, 0, tzinfo=WARSAW),
    )

    timetable.service_calendar.exceptions[("WEEKEND", date(2026, 5, 24))] = (
        ServiceException.REMOVED
    )
    assert [d.line for d in timetable.departures_in_window(BRZEG, window)] == ["D7"]

    timetable.service_calendar.exceptions[("WEEKEND", date(2026, 5, 23))] = (
        ServiceException.REMOVED
    )
    assert timetable.departures_in_window(BRZEG, window) == []


def test_query_window_is_start_inclusive_and_end_exclusive() -> None:
    timetable = _timetable()
    scheduled = datetime(2026, 5, 24, 1, 10, tzinfo=WARSAW)

    starts_at_departure = QueryWindow(
        scheduled,
        datetime(2026, 5, 24, 2, 0, tzinfo=WARSAW),
    )
    ends_at_departure = QueryWindow(
        datetime(2026, 5, 24, 0, 30, tzinfo=WARSAW),
        scheduled,
    )

    assert [
        d.line for d in timetable.departures_in_window(BRZEG, starts_at_departure)
    ] == ["D7"]
    assert timetable.departures_in_window(BRZEG, ends_at_departure) == []


def test_equivalent_utc_and_warsaw_windows_return_identical_departures() -> None:
    timetable = _timetable()
    warsaw_window = QueryWindow(
        datetime(2026, 5, 24, 0, 30, tzinfo=WARSAW),
        datetime(2026, 5, 24, 2, 0, tzinfo=WARSAW),
    )
    utc_window = QueryWindow(
        datetime(2026, 5, 23, 22, 30, tzinfo=UTC),
        datetime(2026, 5, 24, 0, 0, tzinfo=UTC),
    )

    warsaw_departures = timetable.departures_in_window(BRZEG, warsaw_window)
    utc_departures = timetable.departures_in_window(BRZEG, utc_window)
    assert [
        (d.line, d.departure_time, d.platform) for d in warsaw_departures
    ] == [(d.line, d.departure_time, d.platform) for d in utc_departures]


def test_departures_are_sorted_by_utc_instant_across_autumn_fold() -> None:
    station = Station(
        id="station",
        name="Station",
        code=None,
        lat=0,
        lon=0,
        platforms=[],
    )
    timetable = Timetable(
        stations={station.id: station},
        trips={
            "before-fold": Trip(
                id="before-fold",
                route_id="A",
                service_id="SATURDAY",
                headsign=None,
            ),
            "after-fold": Trip(
                id="after-fold",
                route_id="B",
                service_id="SUNDAY",
                headsign=None,
            ),
        },
        routes={
            "A": Route(id="A", short_name="A"),
            "B": Route(id="B", short_name="B"),
        },
        service_calendar=ServiceCalendar(
            patterns={},
            exceptions={
                ("SATURDAY", date(2026, 10, 24)): ServiceException.ADDED,
                ("SUNDAY", date(2026, 10, 25)): ServiceException.ADDED,
            },
        ),
        stop_times_by_stop={
            station.id: [
                StopTime(
                    trip_id="before-fold",
                    stop_id=station.id,
                    stop_sequence=1,
                    arrival_seconds=26 * 3600 + 30 * 60,
                    departure_seconds=26 * 3600 + 30 * 60,
                    pickup_type=0,
                ),
                StopTime(
                    trip_id="after-fold",
                    stop_id=station.id,
                    stop_sequence=1,
                    arrival_seconds=2 * 3600 + 15 * 60,
                    departure_seconds=2 * 3600 + 15 * 60,
                    pickup_type=0,
                ),
            ]
        },
        provider_timezone=WARSAW,
    )
    window = QueryWindow(
        datetime(2026, 10, 25, 2, 0, tzinfo=WARSAW, fold=0),
        datetime(2026, 10, 25, 3, 0, tzinfo=WARSAW),
    )

    departures = timetable.departures_in_window(station.id, window)

    assert [departure.line for departure in departures] == ["A", "B"]
    assert [departure.departure_time.fold for departure in departures] == [0, 1]


def test_simultaneous_departures_use_line_as_the_first_tie_breaker() -> None:
    station = Station(
        id="station",
        name="Station",
        code=None,
        lat=0,
        lon=0,
        platforms=[],
    )
    timetable = Timetable(
        stations={station.id: station},
        trips={
            "a-trip": Trip(
                id="a-trip",
                route_id="route-b",
                service_id="SERVICE",
                headsign=None,
            ),
            "z-trip": Trip(
                id="z-trip",
                route_id="route-a",
                service_id="SERVICE",
                headsign=None,
            ),
        },
        routes={
            "route-a": Route(id="route-a", short_name="A"),
            "route-b": Route(id="route-b", short_name="B"),
        },
        service_calendar=ServiceCalendar(
            patterns={},
            exceptions={
                ("SERVICE", date(2026, 5, 20)): ServiceException.ADDED,
            },
        ),
        stop_times_by_stop={
            station.id: [
                StopTime(
                    trip_id="a-trip",
                    stop_id=station.id,
                    stop_sequence=1,
                    arrival_seconds=5 * 3600 + 30 * 60,
                    departure_seconds=5 * 3600 + 30 * 60,
                    pickup_type=0,
                ),
                StopTime(
                    trip_id="z-trip",
                    stop_id=station.id,
                    stop_sequence=1,
                    arrival_seconds=5 * 3600 + 30 * 60,
                    departure_seconds=5 * 3600 + 30 * 60,
                    pickup_type=0,
                ),
            ]
        },
        provider_timezone=WARSAW,
    )
    window = QueryWindow(
        datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW),
        datetime(2026, 5, 20, 6, 0, tzinfo=WARSAW),
    )

    departures = timetable.departures_in_window(station.id, window)

    assert [departure.line for departure in departures] == ["A", "B"]


def test_maximum_service_day_seconds_uses_arrivals_and_departures() -> None:
    timetable = Timetable(
        stations={},
        trips={},
        routes={},
        service_calendar=ServiceCalendar(patterns={}, exceptions={}),
        stop_times_by_stop={
            "stop": [
                StopTime(
                    trip_id="trip",
                    stop_id="stop",
                    stop_sequence=1,
                    arrival_seconds=100_000,
                    departure_seconds=90_000,
                    pickup_type=0,
                )
            ]
        },
        provider_timezone=WARSAW,
    )

    assert timetable.maximum_service_day_seconds == 100_000
