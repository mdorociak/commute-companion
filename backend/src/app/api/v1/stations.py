from typing import Annotated

from fastapi import APIRouter, Depends, Request

from ...gtfs.models import Station

router = APIRouter()


def station_map(request: Request) -> dict[str, Station]:
    return request.app.state.active_export.require().stations


@router.get("/stations")
def list_stations(
    stations: Annotated[dict[str, Station], Depends(station_map)],
) -> list[Station]:
    results = list(stations.values())
    results.sort(key=lambda station: station.name)
    return results
