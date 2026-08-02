from fastapi import APIRouter

from .departures import router as departures_router
from .stations import router as stations_router

router = APIRouter(prefix="/api/v1")
router.include_router(stations_router)
router.include_router(departures_router)
