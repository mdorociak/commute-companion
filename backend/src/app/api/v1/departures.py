from datetime import datetime
from typing import Annotated
from zoneinfo import ZoneInfo

from fastapi import APIRouter, Depends, Request
from fastapi.responses import JSONResponse

from ...departure_listing import (
    ListDepartures,
    SameOriginAndDestination,
    UnknownStation,
)
from ...timetable import Departure

router = APIRouter()

WARSAW = ZoneInfo("Europe/Warsaw")


def current_time() -> datetime:
    return datetime.now(WARSAW)


def departure_listing(request: Request) -> ListDepartures:
    return request.app.state.departure_listing


def unknown_station_error(request: Request, exc: UnknownStation) -> JSONResponse:
    return JSONResponse(
        status_code=404,
        content={"code": "unknown_station", "reference": exc.reference},
    )


def same_origin_and_destination_error(
    request: Request,
    exc: SameOriginAndDestination,
) -> JSONResponse:
    return JSONResponse(
        status_code=400,
        content={"code": "same_origin_and_destination", "reference": "towards"},
    )


@router.get("/stations/{station_id}/departures")
def list_departures(
    station_id: str,
    listing: Annotated[ListDepartures, Depends(departure_listing)],
    now: Annotated[datetime, Depends(current_time)],
    towards: str | None = None,
) -> list[Departure]:
    return listing.execute(station_id, now, towards_station_id=towards)
