import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI

from .active_export import ActiveExport, load_export
from .api.v1.departures import (
    outside_feed_validity_error,
    same_origin_and_destination_error,
    unknown_station_error,
)
from .api.v1.router import router as api_v1_router
from .departure_listing import (
    OutsideFeedValidity,
    SameOriginAndDestination,
    UnknownStation,
)

_DEFAULT_GTFS_DIR = Path(__file__).resolve().parents[2] / "data" / "kd_gtfs"


@asynccontextmanager
async def lifespan(app: FastAPI):
    gtfs_dir = Path(os.environ.get("KD_GTFS_DIR", _DEFAULT_GTFS_DIR))
    app.state.active_export = ActiveExport(load_export(gtfs_dir))
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
