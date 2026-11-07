from dataclasses import dataclass
from pathlib import Path
from zoneinfo import ZoneInfo

from .departure_listing import ListDepartures
from .gtfs.loader import load_feed_info, load_routes, load_stations, load_trips
from .gtfs.models import FeedInfo, Station
from .gtfs.service_calendar import ServiceCalendar, load_service_calendar
from .gtfs.service_day import ServiceDateRange
from .gtfs.stop_times import load_stop_times
from .timetable import Timetable

_PROVIDER_ID = "kd"
_PROVIDER_TIMEZONE = ZoneInfo("Europe/Warsaw")


@dataclass(frozen=True)
class LoadedExport:
    departure_listing: ListDepartures
    stations: dict[str, Station]
    feed_info: FeedInfo | None


@dataclass
class ActiveExport:
    current: LoadedExport

    def install(self, gtfs_dir: Path) -> None:
        self.current = load_export(gtfs_dir)


def load_export(gtfs_dir: Path) -> LoadedExport:
    feed_info = _load_feed_info(gtfs_dir)
    timetable = _build_timetable(gtfs_dir, _feed_validity(feed_info))
    return LoadedExport(
        departure_listing=ListDepartures(timetable),
        stations=timetable.stations,
        feed_info=feed_info,
    )


def _build_timetable(gtfs_dir: Path, validity: ServiceDateRange) -> Timetable:
    if not (gtfs_dir / "stops.txt").exists():
        return Timetable(
            provider_id=_PROVIDER_ID,
            stations={},
            trips={},
            routes={},
            service_calendar=ServiceCalendar(patterns={}, exceptions={}),
            stop_times_by_stop={},
            provider_timezone=_PROVIDER_TIMEZONE,
            validity=validity,
        )
    return Timetable(
        provider_id=_PROVIDER_ID,
        stations=load_stations(gtfs_dir),
        trips=load_trips(gtfs_dir),
        routes=load_routes(gtfs_dir),
        service_calendar=load_service_calendar(gtfs_dir),
        stop_times_by_stop=load_stop_times(gtfs_dir),
        provider_timezone=_PROVIDER_TIMEZONE,
        validity=validity,
    )


def _load_feed_info(gtfs_dir: Path) -> FeedInfo | None:
    if (gtfs_dir / "feed_info.txt").exists():
        return load_feed_info(gtfs_dir)
    return None


def _feed_validity(feed_info: FeedInfo | None) -> ServiceDateRange:
    if feed_info is None:
        return ServiceDateRange()
    return ServiceDateRange(first=feed_info.start_date, last=feed_info.end_date)
