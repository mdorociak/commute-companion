from datetime import UTC, date, datetime
from typing import TypeVar

from google.protobuf.message import Message
from google.protobuf.unknown_fields import UnknownFieldSet
from google.transit import gtfs_realtime_pb2

from .models import (
    RealtimeSnapshot,
    Rejection,
    RejectionReason,
    StopRelationship,
    StopUpdate,
    TripRelationship,
    TripUpdate,
    VehiclePosition,
)

_TripDescriptor = gtfs_realtime_pb2.TripDescriptor
_StopTimeUpdate = gtfs_realtime_pb2.TripUpdate.StopTimeUpdate
_Relationship = TypeVar("_Relationship", TripRelationship, StopRelationship)


class _Rejected(Exception):
    def __init__(self, reason: RejectionReason) -> None:
        super().__init__(reason)
        self.reason = reason


def parse_feed(data: bytes) -> RealtimeSnapshot:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(data)

    trip_updates: list[TripUpdate] = []
    vehicle_positions: list[VehiclePosition] = []
    rejections: list[Rejection] = []

    for entity in feed.entity:
        if entity.HasField("trip_update"):
            try:
                trip_update = _parse_trip_update(entity.id, entity.trip_update)
            except _Rejected as rejected:
                rejections.append(Rejection(entity.id, rejected.reason))
            else:
                trip_updates.append(trip_update)
                rejections.extend(_delays_without_time(entity.id, entity.trip_update))
        if entity.HasField("vehicle"):
            vp = _parse_vehicle(entity.vehicle)
            if vp is not None:
                vehicle_positions.append(vp)

    return RealtimeSnapshot(
        feed_timestamp=_instant(feed.header, "timestamp"),
        trip_updates=tuple(trip_updates),
        vehicle_positions=tuple(vehicle_positions),
        rejections=tuple(rejections),
    )


def _parse_trip_update(
    entity_id: str, trip_update: gtfs_realtime_pb2.TripUpdate
) -> TripUpdate:
    trip = trip_update.trip
    if not trip.trip_id:
        raise _Rejected(RejectionReason.MISSING_TRIP_ID)

    start_date = (
        _parse_start_date(trip.start_date) if trip.HasField("start_date") else None
    )
    relationship = _relationship(
        trip, TripRelationship, RejectionReason.UNKNOWN_TRIP_RELATIONSHIP
    )
    stops = tuple(_parse_stop(stop) for stop in trip_update.stop_time_update)
    if len({stop.stop_sequence for stop in stops}) != len(stops):
        raise _Rejected(RejectionReason.REPEATED_STOP_SEQUENCE)

    return TripUpdate(
        entity_id=entity_id,
        trip_id=trip.trip_id,
        start_date=start_date,
        relationship=relationship,
        vehicle_id=trip_update.vehicle.id if trip_update.HasField("vehicle") else None,
        stops=stops,
    )


def _parse_start_date(raw: str) -> date:
    if len(raw) != 8 or not raw.isdigit():
        raise _Rejected(RejectionReason.MALFORMED_START_DATE)
    try:
        return date.fromisoformat(raw)
    except ValueError:
        raise _Rejected(RejectionReason.MALFORMED_START_DATE) from None


def _parse_stop(stop: _StopTimeUpdate) -> StopUpdate:
    if not stop.HasField("stop_sequence"):
        raise _Rejected(RejectionReason.MISSING_STOP_SEQUENCE)

    return StopUpdate(
        stop_sequence=stop.stop_sequence,
        stop_id=stop.stop_id or None,
        arrival_time=_instant(stop.arrival, "time"),
        departure_time=_instant(stop.departure, "time"),
        relationship=_relationship(
            stop, StopRelationship, RejectionReason.UNKNOWN_STOP_RELATIONSHIP
        ),
    )


def _relationship(
    message: _TripDescriptor | _StopTimeUpdate,
    relationship: type[_Relationship],
    reason: RejectionReason,
) -> _Relationship:
    field_number = message.SCHEDULE_RELATIONSHIP_FIELD_NUMBER
    if any(field.field_number == field_number for field in UnknownFieldSet(message)):
        raise _Rejected(reason)
    try:
        return relationship(message.schedule_relationship)
    except ValueError:
        raise _Rejected(reason) from None


def _instant(message: Message, field: str) -> datetime | None:
    if not message.HasField(field):
        return None
    return datetime.fromtimestamp(getattr(message, field), tz=UTC)


def _delays_without_time(
    entity_id: str, trip_update: gtfs_realtime_pb2.TripUpdate
) -> list[Rejection]:
    return [
        Rejection(entity_id, RejectionReason.DELAY_WITHOUT_TIME)
        for stop in trip_update.stop_time_update
        for event in (stop.arrival, stop.departure)
        if event.HasField("delay") and not event.HasField("time")
    ]


def _parse_vehicle(v) -> VehiclePosition | None:
    vehicle_id = v.vehicle.id if v.HasField("vehicle") else ""
    if not vehicle_id:
        return None

    return VehiclePosition(
        vehicle_id=vehicle_id,
        latitude=v.position.latitude,
        longitude=v.position.longitude,
        timestamp=v.timestamp,
    )
