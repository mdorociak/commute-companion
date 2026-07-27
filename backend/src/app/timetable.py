from dataclasses import dataclass
from datetime import datetime, time, timedelta

from pydantic import BaseModel

from .gtfs.models import Route, Station, Trip
from .gtfs.service_calendar import ServiceCalendar
from .gtfs.stop_times import StopTime


class Departure(BaseModel):
    line: str
    destination: str | None
    departure_time: datetime
    platform: str | None


@dataclass
class Timetable:
    stations: dict[str, Station]
    trips: dict[str, Trip]
    routes: dict[str, Route]
    service_calendar: ServiceCalendar
    stop_times_by_stop: dict[str, list[StopTime]]

    def next_departures(
        self, station_id: str, now: datetime, limit: int = 10
    ) -> list[Departure]:
        station = self.stations.get(station_id)
        if station is None:
            return []

        service_date = now.date()
        now_seconds = now.hour * 3600 + now.minute * 60 + now.second
        midnight = datetime.combine(service_date, time(), tzinfo=now.tzinfo)

        if station.platforms:
            targets = [(p.id, p.code) for p in station.platforms]
        else:
            targets = [(station.id, None)]

        departures: list[Departure] = []
        for stop_id, platform_code in targets:
            for st in self.stop_times_by_stop.get(stop_id, []):
                if st.pickup_type == 1:
                    continue 
                if st.departure_seconds < now_seconds:
                    continue
                trip = self.trips.get(st.trip_id)
                if trip is None:
                    continue
                if not self.service_calendar.runs_on(trip.service_id, service_date):
                    continue
                route = self.routes.get(trip.route_id)
                departures.append(
                    Departure(
                        line=route.short_name if route else trip.route_id,
                        destination=trip.headsign,
                        departure_time=midnight
                        + timedelta(seconds=st.departure_seconds),
                        platform=platform_code,
                    )
                )

        departures.sort(key=lambda d: d.departure_time)
        return departures[:limit]