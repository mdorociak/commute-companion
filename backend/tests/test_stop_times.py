from pathlib import Path

from app.gtfs.stop_times import load_stop_times

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"

BRZEG_PLATFORM = "2333170"
BRZEG_DOLNY_PLATFORM = "1536298"


def test_load_stop_times_groups_by_stop() -> None:
    by_stop = load_stop_times(FIXTURE_DIR)
    assert BRZEG_PLATFORM in by_stop
    assert BRZEG_DOLNY_PLATFORM in by_stop


def test_brzeg_departures_are_sorted_by_departure_time() -> None:
    brzeg = load_stop_times(FIXTURE_DIR)[BRZEG_PLATFORM]
    trip_order = [st.trip_id for st in brzeg]
    assert trip_order == [
        "38645733_409036",
        "11111111_409036",
        "22222222_409037",
    ]


def test_past_midnight_time_parses_beyond_one_day() -> None:
    brzeg = load_stop_times(FIXTURE_DIR)[BRZEG_PLATFORM]
    after_midnight = brzeg[-1]
    assert after_midnight.trip_id == "22222222_409037"
    assert after_midnight.departure_seconds == 25 * 3600 + 10 * 60  # 90600


def test_row_with_empty_departure_is_skipped() -> None:
    dolny = load_stop_times(FIXTURE_DIR)[BRZEG_DOLNY_PLATFORM]
    assert all(st.trip_id != "22222222_409037" for st in dolny)


def test_pickup_type_is_captured() -> None:
    dolny = load_stop_times(FIXTURE_DIR)[BRZEG_DOLNY_PLATFORM]
    no_pickup = [st for st in dolny if st.pickup_type == 1]
    assert len(no_pickup) == 1
    assert no_pickup[0].trip_id == "11111111_409036"


def test_arrival_and_departure_seconds_are_distinct_when_they_differ() -> None:
    dolny = load_stop_times(FIXTURE_DIR)[BRZEG_DOLNY_PLATFORM]
    st = next(s for s in dolny if s.trip_id == "38645733_409036")
    assert st.arrival_seconds == 6 * 3600 + 10 * 60  # 06:10:00 -> 22200
    assert st.departure_seconds == 6 * 3600 + 12 * 60  # 06:12:00 -> 22320