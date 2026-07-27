from __future__ import annotations
from pydantic import BaseModel


class StopUpdate(BaseModel):
 
    stop_sequence: int
    arrival_time: int | None = None
    departure_time: int | None = None


class TripUpdate(BaseModel):
    trip_id: str
    vehicle_id: str | None = None
    # Keyed by stop_sequence for O(1) merge with static stop_times.
    stops: dict[int, StopUpdate]


class VehiclePosition(BaseModel):
    vehicle_id: str
    latitude: float
    longitude: float
    timestamp: int


class RealtimeSnapshot(BaseModel):
    feed_timestamp: int
    trip_updates: dict[str, TripUpdate]   # trip_id -> TripUpdate
    vehicle_positions: list[VehiclePosition]