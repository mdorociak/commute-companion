import logging
import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI

from .active_export import ActiveExport, TimetableUnavailable
from .api.v1.departures import (
    outside_feed_validity_error,
    same_origin_and_destination_error,
    unknown_station_error,
)
from .api.v1.errors import timetable_unavailable_error
from .api.v1.router import router as api_v1_router
from .departure_listing import (
    OutsideFeedValidity,
    SameOriginAndDestination,
    UnknownStation,
)

_DEFAULT_GTFS_DIR = Path(__file__).resolve().parents[2] / "data" / "kd_gtfs"

logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    gtfs_dir = Path(os.environ.get("KD_GTFS_DIR", _DEFAULT_GTFS_DIR))
    active_export = ActiveExport()
    try:
        active_export.install(gtfs_dir)
    except Exception:
        logger.exception(
            "No timetable loaded from %s; departures and stations answer 503 "
            "until an export is installed",
            gtfs_dir,
        )
    app.state.active_export = active_export
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
app.add_exception_handler(TimetableUnavailable, timetable_unavailable_error)
