from dataclasses import dataclass
from datetime import date, datetime
from enum import IntEnum, StrEnum


class TripRelationship(IntEnum):
    SCHEDULED = 0
    ADDED = 1
    UNSCHEDULED = 2
    CANCELED = 3
    REPLACEMENT = 5
    DUPLICATED = 6


class StopRelationship(IntEnum):
    SCHEDULED = 0
    SKIPPED = 1
    NO_DATA = 2
    UNSCHEDULED = 3


class RejectionReason(StrEnum):
    MISSING_TRIP_ID = "missing_trip_id"
    MISSING_STOP_SEQUENCE = "missing_stop_sequence"
    REPEATED_STOP_SEQUENCE = "repeated_stop_sequence"
    MALFORMED_START_DATE = "malformed_start_date"
    UNKNOWN_TRIP_RELATIONSHIP = "unknown_trip_relationship"
    UNKNOWN_STOP_RELATIONSHIP = "unknown_stop_relationship"
    DELAY_WITHOUT_TIME = "delay_without_time"


@dataclass(frozen=True)
class StopUpdate:
    stop_sequence: int
    stop_id: str | None
    arrival_time: datetime | None
    departure_time: datetime | None
    relationship: StopRelationship


@dataclass(frozen=True)
class TripUpdate:
    entity_id: str
    trip_id: str
    start_date: date | None
    relationship: TripRelationship
    vehicle_id: str | None
    stops: tuple[StopUpdate, ...]


@dataclass(frozen=True)
class Rejection:
    entity_id: str
    reason: RejectionReason


@dataclass(frozen=True)
class VehiclePosition:
    vehicle_id: str
    latitude: float
    longitude: float
    timestamp: int


@dataclass(frozen=True)
class RealtimeSnapshot:
    feed_timestamp: datetime | None
    trip_updates: tuple[TripUpdate, ...]
    vehicle_positions: tuple[VehiclePosition, ...]
    rejections: tuple[Rejection, ...]
