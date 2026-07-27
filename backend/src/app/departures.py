from datetime import datetime
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Request

from .timetable import Departure, Timetable

router = APIRouter()

WARSAW = ZoneInfo("Europe/Warsaw")


def current_time() -> datetime:
    return datetime.now(WARSAW)


@router.get("/departures")
def list_departures(
    request: Request,
    station_id: str,
    now: datetime = Depends(current_time),
) -> list[Departure]:
    timetable: Timetable = request.app.state.timetable
    return timetable.next_departures(station_id, now)