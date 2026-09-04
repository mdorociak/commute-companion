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

    def _station_stops(self, station_id: str) -> list[tuple[str, str | None]]:
        station = self.stations.get(station_id)
        if station is None:
            return []
        if station.platforms:
            return [(platform.id, platform.code) for platform in station.platforms]
        return [(station.id, None)]

    def _furthest_call_by_trip(self, station_id: str) -> dict[str, int]:
        furthest: dict[str, int] = {}
        for stop_id, _ in self._station_stops(station_id):
            for stop_time in self.stop_times_by_stop.get(stop_id, []):
                current = furthest.get(stop_time.trip_id)
                if current is None or stop_time.stop_sequence > current:
                    furthest[stop_time.trip_id] = stop_time.stop_sequence
        return furthest

    def departures_in_window(
        self,
        station_id: str,
        window: QueryWindow,
        limit: int = 10,
        towards_station_id: str | None = None,
    ) -> list[Departure]:
        station = self.stations.get(station_id)
        if station is None or limit <= 0:
            return []

        origin_stops = self._station_stops(station_id)
        furthest_call = (
            None
            if towards_station_id is None
            else self._furthest_call_by_trip(towards_station_id)
        )

        candidates: dict[
            tuple[ScheduledStopEventIdentity, datetime],
            ScheduledDepartureCandidate,
        ] = {}
        service_dates = self._service_day_resolver.candidate_service_dates(
            window,
            self.maximum_service_day_seconds,
        )
        for service_date in service_dates:
            for stop_id, platform_code in origin_stops:
                for stop_time in self.stop_times_by_stop.get(stop_id, []):
                    if stop_time.pickup_type == 1:
                        continue
                    if furthest_call is not None:
                        call = furthest_call.get(stop_time.trip_id)
                        if call is None or call <= stop_time.stop_sequence:
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
