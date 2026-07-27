import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI

from .gtfs.models import FeedInfo
from .departures import router as departures_router
from .gtfs.loader import load_routes, load_stations, load_trips, load_feed_info
from .gtfs.service_calendar import ServiceCalendar, load_service_calendar
from .gtfs.stop_times import load_stop_times
from .stops import router as stops_router
from .timetable import Timetable
from .feed_info import router as feed_info_router

_DEFAULT_GTFS_DIR = Path(__file__).resolve().parents[2] / "data" / "kd_gtfs"

@asynccontextmanager
async def lifespan(app: FastAPI):
    gtfs_dir = Path(os.environ.get("KD_GTFS_DIR", _DEFAULT_GTFS_DIR))
    timetable = _build_timetable(gtfs_dir)
    app.state.timetable = timetable
    app.state.stations = timetable.stations
    app.state.feed_info = _load_feed_info(gtfs_dir)
    yield


app = FastAPI(title="Commuter Backend", version="0.1.0", lifespan=lifespan)


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


app.include_router(stops_router)
app.include_router(departures_router)
app.include_router(feed_info_router)



def _build_timetable(gtfs_dir: Path) -> Timetable:
    if not (gtfs_dir / "stops.txt").exists():
        return Timetable(
            stations={},
            trips={},
            routes={},
            service_calendar=ServiceCalendar(patterns={}, exceptions={}),
            stop_times_by_stop={},
        )
    return Timetable(
        stations=load_stations(gtfs_dir),
        trips=load_trips(gtfs_dir),
        routes=load_routes(gtfs_dir),
        service_calendar=load_service_calendar(gtfs_dir),
        stop_times_by_stop=load_stop_times(gtfs_dir),
    )

def _load_feed_info(gtfs_dir: Path) -> FeedInfo | None:
    if (gtfs_dir / "feed_info.txt").exists():
        return load_feed_info(gtfs_dir)
    return None