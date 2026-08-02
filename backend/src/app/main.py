import os
from contextlib import asynccontextmanager
from pathlib import Path
from zoneinfo import ZoneInfo

from fastapi import FastAPI

from .api.v1.router import router as api_v1_router
from .departure_listing import ListDepartures
from .gtfs.loader import load_feed_info, load_routes, load_stations, load_trips
from .gtfs.models import FeedInfo
from .gtfs.service_calendar import ServiceCalendar, load_service_calendar
from .gtfs.stop_times import load_stop_times
from .timetable import Timetable

_DEFAULT_GTFS_DIR = Path(__file__).resolve().parents[2] / "data" / "kd_gtfs"
_PROVIDER_TIMEZONE = ZoneInfo("Europe/Warsaw")


@asynccontextmanager
async def lifespan(app: FastAPI):
    gtfs_dir = Path(os.environ.get("KD_GTFS_DIR", _DEFAULT_GTFS_DIR))
    timetable = _build_timetable(gtfs_dir)
    app.state.departure_listing = ListDepartures(timetable)
    app.state.stations = timetable.stations
    app.state.feed_info = _load_feed_info(gtfs_dir)
    yield


app = FastAPI(title="Commuter Backend", version="0.1.0", lifespan=lifespan)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(api_v1_router)


def _build_timetable(gtfs_dir: Path) -> Timetable:
    if not (gtfs_dir / "stops.txt").exists():
        return Timetable(
            stations={},
            trips={},
            routes={},
            service_calendar=ServiceCalendar(patterns={}, exceptions={}),
            stop_times_by_stop={},
            provider_timezone=_PROVIDER_TIMEZONE,
        )
    return Timetable(
        stations=load_stations(gtfs_dir),
        trips=load_trips(gtfs_dir),
        routes=load_routes(gtfs_dir),
        service_calendar=load_service_calendar(gtfs_dir),
        stop_times_by_stop=load_stop_times(gtfs_dir),
        provider_timezone=_PROVIDER_TIMEZONE,
    )


def _load_feed_info(gtfs_dir: Path) -> FeedInfo | None:
    if (gtfs_dir / "feed_info.txt").exists():
        return load_feed_info(gtfs_dir)
    return None
