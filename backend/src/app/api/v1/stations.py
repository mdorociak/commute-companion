from fastapi import APIRouter, Request

from ...gtfs.models import Station

router = APIRouter()


@router.get("/stations")
def list_stations(request: Request, search: str | None = None) -> list[Station]:
    stations: dict[str, Station] = request.app.state.stations
    results = list(stations.values())

    if search:
        needle = search.casefold()
        results = [station for station in results if needle in station.name.casefold()]

    results.sort(key=lambda station: station.name)
    return results
