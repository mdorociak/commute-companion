from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from typing import Literal

from .gtfs.service_day import QueryWindow
from .timetable import Departure, Timetable

DEFAULT_DEPARTURE_HORIZON = timedelta(hours=24)

StationReference = Literal["station_id", "towards"]


class UnknownStation(Exception):
    def __init__(self, station_id: str, reference: StationReference) -> None:
        super().__init__(f"{reference} {station_id!r} does not resolve to a station")
        self.station_id = station_id
        self.reference: StationReference = reference


class SameOriginAndDestination(Exception):
    def __init__(self, station_id: str) -> None:
        super().__init__(f"onward station {station_id!r} is the origin station")
        self.station_id = station_id


@dataclass(frozen=True)
class ListDepartures:
    timetable: Timetable
    horizon: timedelta = DEFAULT_DEPARTURE_HORIZON

    def __post_init__(self) -> None:
        if self.horizon <= timedelta(0):
            raise ValueError("departure horizon must be positive")

    def execute(
        self,
        station_id: str,
        now: datetime,
        limit: int = 10,
        towards_station_id: str | None = None,
    ) -> list[Departure]:
        if now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("now must be timezone-aware")

        self._require_known_station(station_id, "station_id")
        if towards_station_id is not None:
            self._require_known_station(towards_station_id, "towards")
            if towards_station_id == station_id:
                raise SameOriginAndDestination(station_id)

        start_utc = now.astimezone(UTC)
        window = QueryWindow(start_utc, start_utc + self.horizon)
        return self.timetable.departures_in_window(
            station_id,
            window,
            limit=limit,
            towards_station_id=towards_station_id,
        )

    def _require_known_station(
        self,
        station_id: str,
        reference: StationReference,
    ) -> None:
        if station_id not in self.timetable.stations:
            raise UnknownStation(station_id, reference)
