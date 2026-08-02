from datetime import datetime
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Request

from ...departure_listing import ListDepartures
from ...timetable import Departure

router = APIRouter()

WARSAW = ZoneInfo("Europe/Warsaw")


def current_time() -> datetime:
    return datetime.now(WARSAW)


def departure_listing(request: Request) -> ListDepartures:
    return request.app.state.departure_listing


@router.get("/stations/{station_id}/departures")
def list_departures(
    station_id: str,
    listing: Annotated[ListDepartures, Depends(departure_listing)],
    now: Annotated[datetime, Depends(current_time)],
) -> list[Departure]:
    return listing.execute(station_id, now)
