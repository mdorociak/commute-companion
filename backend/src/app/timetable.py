from dataclasses import dataclass, field
from datetime import date, datetime
from zoneinfo import ZoneInfo

from pydantic import BaseModel

from .gtfs.models import Route, Station, Trip
from .gtfs.service_calendar import ServiceCalendar
from .gtfs.service_day import QueryWindow, ServiceDayResolver
from .gtfs.stop_times import StopTime


class Departure(BaseModel):
    line: str
    destination: str | None
    departure_time: datetime
    platform: str | None


@dataclass(frozen=True)
class ScheduledDepartureCandidate:
    service_date: date
    scheduled_utc: datetime
    trip_id: str
    stop_id: str
    stop_sequence: int
    line: str
    destination: str | None
    platform: str | None


@dataclass
class Timetable:
    stations: dict[str, Station]
    trips: dict[str, Trip]
    routes: dict[str, Route]
    service_calendar: ServiceCalendar
    stop_times_by_stop: dict[str, list[StopTime]]
    provider_timezone: ZoneInfo
    maximum_service_day_seconds: int = field(init=False)
    _service_day_resolver: ServiceDayResolver = field(init=False, repr=False)

    def __post_init__(self) -> None:
        self._service_day_resolver = ServiceDayResolver(self.provider_timezone)
        self.maximum_service_day_seconds = max(
            (
                seconds
                for stop_times in self.stop_times_by_stop.values()
                for stop_time in stop_times
                for seconds in (
                    stop_time.arrival_seconds,
                    stop_time.departure_seconds,
                )
            ),
            default=0,
        )

    def departures_in_window(
        self,
        station_id: str,
        window: QueryWindow,
        limit: int = 10,
    ) -> list[Departure]:
        station = self.stations.get(station_id)
        if station is None or limit <= 0:
            return []

        if station.platforms:
            targets = [(p.id, p.code) for p in station.platforms]
        else:
            targets = [(station.id, None)]

        candidates: dict[
            tuple[date, str, str, int, datetime], ScheduledDepartureCandidate
        ] = {}
        service_dates = self._service_day_resolver.candidate_service_dates(
            window,
            self.maximum_service_day_seconds,
        )
        for service_date in service_dates:
            for stop_id, platform_code in targets:
                for stop_time in self.stop_times_by_stop.get(stop_id, []):
                    if stop_time.pickup_type == 1:
                        continue
                    trip = self.trips.get(stop_time.trip_id)
                    if trip is None or not self.service_calendar.runs_on(
                        trip.service_id,
                        service_date,
                    ):
                        continue
                    scheduled_utc = self._service_day_resolver.scheduled_instant_utc(
                        service_date,
                        stop_time.departure_seconds,
                    )
                    if not window.start_utc <= scheduled_utc < window.end_utc:
                        continue
                    route = self.routes.get(trip.route_id)
                    candidate = ScheduledDepartureCandidate(
                        service_date=service_date,
                        scheduled_utc=scheduled_utc,
                        trip_id=trip.id,
                        stop_id=stop_id,
                        stop_sequence=stop_time.stop_sequence,
                        line=route.short_name if route else trip.route_id,
                        destination=trip.headsign,
                        platform=platform_code,
                    )
                    identity = (
                        candidate.service_date,
                        candidate.trip_id,
                        candidate.stop_id,
                        candidate.stop_sequence,
                        candidate.scheduled_utc,
                    )
                    candidates[identity] = candidate

        ordered = sorted(
            candidates.values(),
            key=lambda candidate: (
                candidate.scheduled_utc,
                candidate.line,
                candidate.trip_id,
                candidate.stop_sequence,
                candidate.stop_id,
                candidate.service_date,
            ),
        )
        return [
            Departure(
                line=candidate.line,
                destination=candidate.destination,
                departure_time=candidate.scheduled_utc.astimezone(
                    self.provider_timezone
                ),
                platform=candidate.platform,
            )
            for candidate in ordered[:limit]
        ]
