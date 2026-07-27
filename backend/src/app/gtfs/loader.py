import csv
from pathlib import Path
from datetime import datetime

from .models import Platform, Route, Station, Trip, FeedInfo

def _gtfs_date(value: str):
    value = value.strip()
    return datetime.strptime(value, "%Y%m%d").date() if value else None

def load_stations(gtfs_dir: Path) -> dict[str, Station]:

    stops_file = gtfs_dir / "stops.txt"
    stations: dict[str, Station] = {}
    platform_rows: list[dict[str, str]] = []

    with stops_file.open(encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            location_type = row.get("location_type", "").strip()
            if location_type == "1":
                stations[row["stop_id"]] = Station(
                    id=row["stop_id"],
                    name=row["stop_name"],
                    code=row.get("stop_code") or None,
                    lat=float(row["stop_lat"]),
                    lon=float(row["stop_lon"]),
                    platforms=[],
                )
            elif location_type == "0":
                platform_rows.append(row)

    for row in platform_rows:
        parent_id = row.get("parent_station", "")
        station = stations.get(parent_id)
        if station is None:
            continue
        station.platforms.append(
            Platform(
                id=row["stop_id"],
                code=row.get("platform_code") or None,
            )
        )

    return stations
def load_routes(gtfs_dir: Path) -> dict[str, Route]:
    routes_file = gtfs_dir / "routes.txt"
    routes: dict[str, Route] = {}

    with routes_file.open(encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            routes[row["route_id"]] = Route(
                id=row["route_id"],
                short_name=row["route_short_name"],
            )

    return routes


def load_trips(gtfs_dir: Path) -> dict[str, Trip]:
    trips_file = gtfs_dir / "trips.txt"
    trips: dict[str, Trip] = {}

    with trips_file.open(encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            trips[row["trip_id"]] = Trip(
                id=row["trip_id"],
                route_id=row["route_id"],
                service_id=row["service_id"],
                headsign=row.get("trip_headsign") or None,
            )

    return trips

def load_feed_info(gtfs_dir: Path) -> FeedInfo:
    with (gtfs_dir / "feed_info.txt").open(encoding="utf-8") as f:
        row = next(csv.DictReader(f))
    return FeedInfo(
        publisher_name=row["feed_publisher_name"],
        publisher_url=row["feed_publisher_url"],
        lang=row["feed_lang"],
        start_date=_gtfs_date(row.get("feed_start_date", "")),
        end_date=_gtfs_date(row.get("feed_end_date", ""))
    )