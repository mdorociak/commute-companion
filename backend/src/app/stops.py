
from fastapi import APIRouter, Request

from .gtfs.models import Station

router = APIRouter()


@router.get("/stops")
def list_stops(request: Request, search: str | None = None) -> list[Station]:
    stations: dict[str, Station] = request.app.state.stations
    results = list(stations.values())

    if search:
        needle = search.casefold()
        results = [s for s in results if needle in s.name.casefold()]

    results.sort(key=lambda s: s.name)
    return results
