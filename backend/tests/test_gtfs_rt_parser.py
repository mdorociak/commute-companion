from datetime import UTC, date, datetime, timedelta
from pathlib import Path

import pytest
from google.transit import gtfs_realtime_pb2

from app.gtfs_rt.models import (
    RealtimeSnapshot,
    Rejection,
    RejectionReason,
    StopRelationship,
    TripRelationship,
)
from app.gtfs_rt.parser import parse_feed
from tests.fixtures.mock_gtfs.build_rt_fixture import build_fixture

StopTimeUpdate = gtfs_realtime_pb2.TripUpdate.StopTimeUpdate

ARRIVAL = datetime(2026, 10, 27, 5, 14, tzinfo=UTC)
DEPARTURE = datetime(2026, 10, 27, 5, 15, tzinfo=UTC)
UNDEFINED_ENUM_VALUE = 99


@pytest.fixture
def rt_bytes(tmp_path: Path) -> bytes:
    pb = tmp_path / "rt_sample.pb"
    build_fixture(pb)
    return pb.read_bytes()


def _feed() -> gtfs_realtime_pb2.FeedMessage:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.header.gtfs_realtime_version = "2.0"
    feed.header.timestamp = int(DEPARTURE.timestamp())
    return feed


def _trip_update(
    feed: gtfs_realtime_pb2.FeedMessage, entity_id: str = "e1", trip_id: str = "TRIP_A"
) -> gtfs_realtime_pb2.TripUpdate:
    entity = feed.entity.add()
    entity.id = entity_id
    entity.trip_update.trip.trip_id = trip_id
    return entity.trip_update


def _stop(trip_update: gtfs_realtime_pb2.TripUpdate, sequence: int) -> StopTimeUpdate:
    stop = trip_update.stop_time_update.add()
    stop.stop_sequence = sequence
    stop.arrival.time = int(ARRIVAL.timestamp())
    stop.departure.time = int(DEPARTURE.timestamp())
    return stop


def _set_undefined_enum(message, field_number: int) -> None:
    message.MergeFromString(bytes([field_number << 3, UNDEFINED_ENUM_VALUE]))


def _parse(feed: gtfs_realtime_pb2.FeedMessage) -> RealtimeSnapshot:
    return parse_feed(feed.SerializeToString())


def test_header_timestamp_becomes_a_utc_instant(rt_bytes: bytes) -> None:
    snapshot = parse_feed(rt_bytes)
    assert snapshot.feed_timestamp == datetime(2026, 6, 7, 18, 8, 20, tzinfo=UTC)
    assert snapshot.feed_timestamp.utcoffset() == timedelta(0)


def test_header_without_timestamp_has_no_feed_timestamp() -> None:
    feed = _feed()
    feed.header.ClearField("timestamp")
    assert _parse(feed).feed_timestamp is None


def test_trip_update_values_are_kept_in_feed_order(rt_bytes: bytes) -> None:
    (trip_update,) = parse_feed(rt_bytes).trip_updates
    assert trip_update.entity_id == "t-TRIP_A"
    assert trip_update.trip_id == "TRIP_A"
    assert trip_update.vehicle_id == "V_100"
    assert [stop.stop_sequence for stop in trip_update.stops] == [2, 5]
    assert [stop.departure_time for stop in trip_update.stops] == [
        datetime(2026, 6, 7, 18, 4, 58, tzinfo=UTC),
        datetime(2026, 6, 7, 18, 21, 58, tzinfo=UTC),
    ]


def test_update_without_trip_id_is_rejected_and_others_are_kept(
    rt_bytes: bytes,
) -> None:
    snapshot = parse_feed(rt_bytes)
    assert [update.trip_id for update in snapshot.trip_updates] == ["TRIP_A"]
    assert snapshot.rejections == (
        Rejection("t-malformed", RejectionReason.MISSING_TRIP_ID),
    )


def test_vehicle_positions_include_non_reporting(rt_bytes: bytes) -> None:
    snapshot = parse_feed(rt_bytes)
    ids = {v.vehicle_id for v in snapshot.vehicle_positions}
    assert ids == {"V_100", "V_200"}
    reporting = next(v for v in snapshot.vehicle_positions if v.vehicle_id == "V_100")
    assert reporting.latitude == pytest.approx(50.852881)
    assert reporting.longitude == pytest.approx(17.470911)


def test_combined_feed_routes_entities_by_type(rt_bytes: bytes) -> None:
    snapshot = parse_feed(rt_bytes)
    assert len(snapshot.trip_updates) == 1
    assert len(snapshot.vehicle_positions) == 2


def test_start_date_becomes_a_service_date() -> None:
    feed = _feed()
    trip_update = _trip_update(feed)
    trip_update.trip.start_date = "20261026"
    _stop(trip_update, 1)
    (parsed,) = _parse(feed).trip_updates
    assert parsed.start_date == date(2026, 10, 26)


def test_absent_start_date_is_none_and_not_a_rejection() -> None:
    feed = _feed()
    _stop(_trip_update(feed), 1)
    snapshot = _parse(feed)
    assert snapshot.trip_updates[0].start_date is None
    assert snapshot.rejections == ()


@pytest.mark.parametrize("raw", ["2026-10-26", "2026W435", "20261340"])
def test_malformed_start_date_rejects_the_update(raw: str) -> None:
    feed = _feed()
    trip_update = _trip_update(feed)
    trip_update.trip.start_date = raw
    _stop(trip_update, 1)
    snapshot = _parse(feed)
    assert snapshot.trip_updates == ()
    assert snapshot.rejections == (
        Rejection("e1", RejectionReason.MALFORMED_START_DATE),
    )


def test_trip_and_stop_relationships_are_kept() -> None:
    feed = _feed()
    trip_update = _trip_update(feed)
    trip_update.trip.schedule_relationship = gtfs_realtime_pb2.TripDescriptor.CANCELED
    _stop(trip_update, 1).schedule_relationship = StopTimeUpdate.SKIPPED
    _stop(trip_update, 2).schedule_relationship = StopTimeUpdate.NO_DATA
    (parsed,) = _parse(feed).trip_updates
    assert parsed.relationship is TripRelationship.CANCELED
    assert parsed.stops[0].relationship is StopRelationship.SKIPPED
    assert parsed.stops[1].relationship is StopRelationship.NO_DATA


def test_unset_relationships_read_as_scheduled() -> None:
    feed = _feed()
    _stop(_trip_update(feed), 1)
    (parsed,) = _parse(feed).trip_updates
    assert parsed.relationship is TripRelationship.SCHEDULED
    assert parsed.stops[0].relationship is StopRelationship.SCHEDULED


def test_relationship_the_merge_does_not_handle_passes_the_adapter() -> None:
    feed = _feed()
    trip_update = _trip_update(feed)
    trip_update.trip.schedule_relationship = gtfs_realtime_pb2.TripDescriptor.ADDED
    _stop(trip_update, 1)
    snapshot = _parse(feed)
    assert snapshot.trip_updates[0].relationship is TripRelationship.ADDED
    assert snapshot.rejections == ()


def test_trip_relationship_undefined_in_the_bindings_rejects_the_update() -> None:
    feed = _feed()
    trip_update = _trip_update(feed)
    _set_undefined_enum(
        trip_update.trip,
        gtfs_realtime_pb2.TripDescriptor.SCHEDULE_RELATIONSHIP_FIELD_NUMBER,
    )
    _stop(trip_update, 1)
    snapshot = _parse(feed)
    assert snapshot.trip_updates == ()
    assert snapshot.rejections == (
        Rejection("e1", RejectionReason.UNKNOWN_TRIP_RELATIONSHIP),
    )


def test_stop_relationship_undefined_in_the_bindings_rejects_the_update() -> None:
    feed = _feed()
    trip_update = _trip_update(feed)
    _stop(trip_update, 1)
    _set_undefined_enum(
        _stop(trip_update, 2), StopTimeUpdate.SCHEDULE_RELATIONSHIP_FIELD_NUMBER
    )
    snapshot = _parse(feed)
    assert snapshot.trip_updates == ()
    assert snapshot.rejections == (
        Rejection("e1", RejectionReason.UNKNOWN_STOP_RELATIONSHIP),
    )


def test_arrival_and_departure_times_become_utc_instants() -> None:
    feed = _feed()
    _stop(_trip_update(feed), 1)
    (stop,) = _parse(feed).trip_updates[0].stops
    assert stop.arrival_time == ARRIVAL
    assert stop.departure_time == DEPARTURE
    assert stop.arrival_time.utcoffset() == timedelta(0)
    assert stop.departure_time.utcoffset() == timedelta(0)


@pytest.mark.parametrize(
    ("event", "other"), [("arrival", "departure"), ("departure", "arrival")]
)
def test_event_with_delay_and_no_time_keeps_no_time_and_is_counted(
    event: str, other: str
) -> None:
    feed = _feed()
    stop = _stop(_trip_update(feed), 1)
    getattr(stop, event).ClearField("time")
    getattr(stop, event).delay = 120
    snapshot = _parse(feed)
    (parsed,) = snapshot.trip_updates[0].stops
    assert getattr(parsed, f"{event}_time") is None
    assert getattr(parsed, f"{other}_time") is not None
    assert snapshot.rejections == (
        Rejection("e1", RejectionReason.DELAY_WITHOUT_TIME),
    )


def test_stop_without_departure_event_has_no_departure_and_no_rejection() -> None:
    feed = _feed()
    _stop(_trip_update(feed), 1).ClearField("departure")
    snapshot = _parse(feed)
    assert snapshot.trip_updates[0].stops[0].departure_time is None
    assert snapshot.rejections == ()


def test_stop_id_is_kept_when_sent_and_none_when_not() -> None:
    feed = _feed()
    trip_update = _trip_update(feed)
    _stop(trip_update, 1).stop_id = "1474824"
    _stop(trip_update, 2)
    (parsed,) = _parse(feed).trip_updates
    assert [stop.stop_id for stop in parsed.stops] == ["1474824", None]


def test_stop_sequence_zero_is_kept() -> None:
    feed = _feed()
    _stop(_trip_update(feed), 0)
    snapshot = _parse(feed)
    assert snapshot.trip_updates[0].stops[0].stop_sequence == 0
    assert snapshot.rejections == ()


def test_two_updates_with_one_trip_id_both_survive_in_feed_order() -> None:
    feed = _feed()
    _stop(_trip_update(feed, entity_id="e1"), 1)
    _stop(_trip_update(feed, entity_id="e2"), 4)
    snapshot = _parse(feed)
    assert [(u.entity_id, u.trip_id) for u in snapshot.trip_updates] == [
        ("e1", "TRIP_A"),
        ("e2", "TRIP_A"),
    ]


def test_stop_without_sequence_rejects_the_whole_update() -> None:
    feed = _feed()
    trip_update = _trip_update(feed)
    _stop(trip_update, 1)
    unsequenced = trip_update.stop_time_update.add()
    unsequenced.stop_id = "1474825"
    unsequenced.departure.time = int(DEPARTURE.timestamp())
    snapshot = _parse(feed)
    assert snapshot.trip_updates == ()
    assert snapshot.rejections == (
        Rejection("e1", RejectionReason.MISSING_STOP_SEQUENCE),
    )


def test_repeated_stop_sequence_rejects_the_whole_update() -> None:
    feed = _feed()
    trip_update = _trip_update(feed)
    _stop(trip_update, 3)
    _stop(trip_update, 3)
    snapshot = _parse(feed)
    assert snapshot.trip_updates == ()
    assert snapshot.rejections == (
        Rejection("e1", RejectionReason.REPEATED_STOP_SEQUENCE),
    )
