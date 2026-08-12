from dataclasses import dataclass, field
from datetime import datetime
from zoneinfo import ZoneInfo

from pydantic import BaseModel

from .departure_identity import ScheduledStopEventIdentity
from .gtfs.models import Route, Station, Trip
from .gtfs.service_calendar import ServiceCalendar
from .gtfs.service_day import QueryWindow, ServiceDayResolver
from .gtfs.stop_times import StopTime


class Departure(BaseModel):
    id: str
    line: str
    destination: str | None
    departure_time: datetime
    platform: str | None


@dataclass(frozen=True)
class ScheduledDepartureCandidate:
    identity: ScheduledStopEventIdentity
    scheduled_utc: datetime
    line: str
    destination: str | None
    platform: str | None


@dataclass
class Timetable:
    provider_id: str
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
            tuple[ScheduledStopEventIdentity, datetime],
            ScheduledDepartureCandidate,
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
                        identity=ScheduledStopEventIdentity(
                            provider_id=self.provider_id,
                            service_date=service_date,
                            provider_trip_id=trip.id,
                            provider_stop_id=stop_id,
                            stop_sequence=stop_time.stop_sequence,
                        ),
                        scheduled_utc=scheduled_utc,
                        line=route.short_name if route else trip.route_id,
                        destination=trip.headsign,
                        platform=platform_code,
                    )
                    identity = (
                        candidate.identity,
                        candidate.scheduled_utc,
                    )
                    candidates[identity] = candidate

        ordered = sorted(
            candidates.values(),
            key=lambda candidate: (
                candidate.scheduled_utc,
                candidate.line,
                candidate.identity.provider_trip_id,
                candidate.identity.stop_sequence,
                candidate.identity.provider_stop_id,
                candidate.identity.service_date,
            ),
        )
        return [
            Departure(
                id=candidate.identity.opaque_id,
                line=candidate.line,
                destination=candidate.destination,
                departure_time=candidate.scheduled_utc.astimezone(
                    self.provider_timezone
                ),
                platform=candidate.platform,
            )
            for candidate in ordered[:limit]
        ]
