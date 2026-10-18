import os
from contextlib import asynccontextmanager
from pathlib import Path
from zoneinfo import ZoneInfo

from fastapi import FastAPI

from .api.v1.departures import (
    outside_feed_validity_error,
    same_origin_and_destination_error,
    unknown_station_error,
)
from .api.v1.router import router as api_v1_router
from .departure_listing import (
    ListDepartures,
    OutsideFeedValidity,
    SameOriginAndDestination,
    UnknownStation,
)
from .gtfs.loader import load_feed_info, load_routes, load_stations, load_trips
from .gtfs.models import FeedInfo
from .gtfs.service_calendar import ServiceCalendar, load_service_calendar
from .gtfs.service_day import ServiceDateRange
from .gtfs.stop_times import load_stop_times
from .timetable import Timetable

_DEFAULT_GTFS_DIR = Path(__file__).resolve().parents[2] / "data" / "kd_gtfs"
_PROVIDER_ID = "kd"
_PROVIDER_TIMEZONE = ZoneInfo("Europe/Warsaw")


@asynccontextmanager
async def lifespan(app: FastAPI):
    gtfs_dir = Path(os.environ.get("KD_GTFS_DIR", _DEFAULT_GTFS_DIR))
    feed_info = _load_feed_info(gtfs_dir)
    timetable = _build_timetable(gtfs_dir, _feed_validity(feed_info))
    app.state.departure_listing = ListDepartures(timetable)
    app.state.stations = timetable.stations
    app.state.feed_info = feed_info
    yield


app = FastAPI(title="Commuter Backend", version="0.1.0", lifespan=lifespan)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(api_v1_router)
app.add_exception_handler(UnknownStation, unknown_station_error)
app.add_exception_handler(
    SameOriginAndDestination,
    same_origin_and_destination_error,
)
app.add_exception_handler(OutsideFeedValidity, outside_feed_validity_error)


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
