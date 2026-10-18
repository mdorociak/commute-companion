from datetime import UTC, date, datetime, timedelta
from pathlib import Path
from zoneinfo import ZoneInfo

import pytest

from app.departure_listing import (
    DEFAULT_DEPARTURE_HORIZON,
    ListDepartures,
    OutsideFeedValidity,
    SameOriginAndDestination,
    UnknownStation,
)
from app.gtfs.loader import load_routes, load_stations, load_trips
from app.gtfs.service_calendar import load_service_calendar
from app.gtfs.service_day import ServiceDateRange
from app.gtfs.stop_times import load_stop_times
from app.timetable import Timetable

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"
WARSAW = ZoneInfo("Europe/Warsaw")

BRZEG = "2246799"
OLAWA = "3000001"
UNKNOWN = "no-such-station"
ALSO_UNKNOWN = "no-such-station-either"


def _listing(
    horizon: timedelta = DEFAULT_DEPARTURE_HORIZON,
    validity: ServiceDateRange | None = None,
) -> ListDepartures:
    return ListDepartures(
        Timetable(
            provider_id="kd",
            stations=load_stations(FIXTURE_DIR),
            trips=load_trips(FIXTURE_DIR),
            routes=load_routes(FIXTURE_DIR),
            service_calendar=load_service_calendar(FIXTURE_DIR),
            stop_times_by_stop=load_stop_times(FIXTURE_DIR),
            provider_timezone=WARSAW,
            validity=validity or ServiceDateRange(),
        ),
        horizon=horizon,
    )


def test_default_horizon_includes_now_and_excludes_the_same_time_tomorrow() -> None:
    now = datetime(2026, 5, 19, 14, 32, tzinfo=WARSAW)

    departures = _listing().execute(BRZEG, now)

    assert [departure.departure_time for departure in departures] == [
        datetime(2026, 5, 19, 14, 32, tzinfo=WARSAW),
        datetime(2026, 5, 20, 5, 36, tzinfo=WARSAW),
    ]


def test_a_non_positive_horizon_is_rejected_at_construction() -> None:
    with pytest.raises(ValueError):
        _listing(horizon=timedelta(0))


def test_a_naive_now_is_rejected() -> None:
    naive = datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW).replace(tzinfo=None)

    with pytest.raises(ValueError):
        _listing().execute(BRZEG, naive)


def test_an_unresolvable_origin_names_the_station_id_reference() -> None:
    now = datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW)

    with pytest.raises(UnknownStation) as error:
        _listing().execute(UNKNOWN, now)

    assert error.value.reference == "station_id"
    assert error.value.station_id == UNKNOWN


def test_an_unresolvable_onward_station_names_the_towards_reference() -> None:
    now = datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW)

    with pytest.raises(UnknownStation) as error:
        _listing().execute(BRZEG, now, towards_station_id=UNKNOWN)

    assert error.value.reference == "towards"
    assert error.value.station_id == UNKNOWN


def test_an_onward_station_equal_to_the_origin_is_rejected() -> None:
    now = datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW)

    with pytest.raises(SameOriginAndDestination) as error:
        _listing().execute(BRZEG, now, towards_station_id=BRZEG)

    assert error.value.station_id == BRZEG


def test_the_origin_is_resolved_before_the_onward_station() -> None:
    now = datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW)

    with pytest.raises(UnknownStation) as error:
        _listing().execute(UNKNOWN, now, towards_station_id=ALSO_UNKNOWN)

    assert error.value.reference == "station_id"


def test_a_resolvable_pair_returns_the_direction_filtered_list() -> None:
    now = datetime(2026, 5, 20, 5, 0, tzinfo=WARSAW)
    listing = _listing()

    unfiltered = listing.execute(BRZEG, now)
    towards_olawa = listing.execute(BRZEG, now, towards_station_id=OLAWA)

    assert [departure.line for departure in unfiltered] == ["D7", "D1"]
    assert [departure.line for departure in towards_olawa] == ["D7"]


def test_limit_is_applied_after_ordering_by_departure_time() -> None:
    now = datetime(2026, 5, 20, 3, 0, tzinfo=UTC)
    listing = _listing()

    full = listing.execute(BRZEG, now)
    limited = listing.execute(BRZEG, now, limit=1)

    assert len(full) > 1
    assert [d.departure_time for d in full] == sorted(d.departure_time for d in full)
    assert limited == full[:1]


def test_a_request_after_the_feeds_final_event_is_outside_validity() -> None:
    listing = _listing(validity=ServiceDateRange(last=date(2026, 5, 23)))

    with pytest.raises(OutsideFeedValidity):
        listing.execute(BRZEG, datetime(2026, 5, 24, 1, 11, tzinfo=WARSAW))


def test_the_last_service_days_late_trip_is_listed_after_midnight() -> None:
    listing = _listing(validity=ServiceDateRange(last=date(2026, 5, 23)))

    departures = listing.execute(BRZEG, datetime(2026, 5, 24, 0, 30, tzinfo=WARSAW))

    assert [departure.departure_time for departure in departures] == [
        datetime(2026, 5, 24, 1, 10, tzinfo=WARSAW)
    ]


def test_a_request_ending_before_the_first_service_day_is_outside_validity() -> None:
    listing = _listing(validity=ServiceDateRange(first=date(2026, 5, 21)))

    with pytest.raises(OutsideFeedValidity):
        listing.execute(BRZEG, datetime(2026, 5, 19, 14, 32, tzinfo=WARSAW))


def test_validity_is_checked_before_station_references() -> None:
    listing = _listing(validity=ServiceDateRange(last=date(2026, 5, 23)))
    now = datetime(2026, 5, 24, 1, 11, tzinfo=WARSAW)

    with pytest.raises(OutsideFeedValidity):
        listing.execute(UNKNOWN, now, towards_station_id=ALSO_UNKNOWN)


def test_a_partly_covered_window_lists_only_the_covered_departures() -> None:
    listing = _listing(validity=ServiceDateRange(last=date(2026, 5, 19)))

    departures = listing.execute(BRZEG, datetime(2026, 5, 19, 14, 32, tzinfo=WARSAW))

    assert [departure.departure_time for departure in departures] == [
        datetime(2026, 5, 19, 14, 32, tzinfo=WARSAW)
    ]
