from fastapi import APIRouter, Request

from ...gtfs.models import Station

router = APIRouter()


@router.get("/stations")
def list_stations(request: Request) -> list[Station]:
    stations: dict[str, Station] = request.app.state.stations
    results = list(stations.values())
    results.sort(key=lambda station: station.name)
    return results
