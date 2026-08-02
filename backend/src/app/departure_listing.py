from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from .gtfs.service_day import QueryWindow
from .timetable import Departure, Timetable


DEFAULT_DEPARTURE_HORIZON = timedelta(hours=24)


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
    ) -> list[Departure]:
        if now.tzinfo is None or now.utcoffset() is None:
            raise ValueError("now must be timezone-aware")

        start_utc = now.astimezone(UTC)
        window = QueryWindow(start_utc, start_utc + self.horizon)
        return self.timetable.departures_in_window(
            station_id,
            window,
            limit=limit,
        )
