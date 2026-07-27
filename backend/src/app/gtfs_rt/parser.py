from google.transit import gtfs_realtime_pb2

from .models import RealtimeSnapshot, StopUpdate, TripUpdate, VehiclePosition


def parse_feed(data: bytes) -> RealtimeSnapshot:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.ParseFromString(data)

    trip_updates: dict[str, TripUpdate] = {}
    vehicle_positions: list[VehiclePosition] = []

    for entity in feed.entity:
        if entity.HasField("trip_update"):
            tu = _parse_trip_update(entity.trip_update)
            if tu is not None:
                trip_updates[tu.trip_id] = tu
        if entity.HasField("vehicle"):
            vp = _parse_vehicle(entity.vehicle)
            if vp is not None:
                vehicle_positions.append(vp)

    return RealtimeSnapshot(
        feed_timestamp=feed.header.timestamp,
        trip_updates=trip_updates,
        vehicle_positions=vehicle_positions,
    )


def _parse_trip_update(tu) -> TripUpdate | None:
    trip_id = tu.trip.trip_id
    if not trip_id:
        return None   # malformed; without trip_id we can't merge it

    stops: dict[int, StopUpdate] = {}
    for stu in tu.stop_time_update:
        # KD always sends stop_sequence; we don't fall back to stop_id today.
        stops[stu.stop_sequence] = StopUpdate(
            stop_sequence=stu.stop_sequence,
            arrival_time=stu.arrival.time if stu.HasField("arrival") else None,
            departure_time=stu.departure.time if stu.HasField("departure") else None,
        )

    return TripUpdate(
        trip_id=trip_id,
        vehicle_id=tu.vehicle.id if tu.HasField("vehicle") else None,
        stops=stops,
    )


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