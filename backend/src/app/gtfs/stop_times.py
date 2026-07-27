import csv
from dataclasses import dataclass
from pathlib import Path

@dataclass(slots=True)
class StopTime:
    trip_id: str
    stop_id: str
    stop_sequence: int
    arrival_seconds: int
    departure_seconds: int
    pickup_type: int

def _parse_gtfs_time(value: str) -> int:
    hours, minutes, seconds = value.split(":")
    return int(hours) * 3600 + int(minutes) * 60 +int(seconds)

def load_stop_times(gtfs_dir: Path) -> dict[str, list[StopTime]]:
    by_stop: dict[str, list[StopTime]] = {}

    with (gtfs_dir / "stop_times.txt").open(encoding="utf-8") as f:
        for row in csv.DictReader(f):
            departure_raw = row["departure_time"].strip()
            if not departure_raw:
                continue
            departure = _parse_gtfs_time(departure_raw)

            arrival_raw = row["arrival_time"].strip()
            arrival = _parse_gtfs_time(arrival_raw) if arrival_raw else departure

            pickup_raw = row.get("pickup_type", "").strip()
            pickup_type = int(pickup_raw) if pickup_raw else 0

            stop_time = StopTime(
                trip_id=row["trip_id"],
                stop_id=row["stop_id"],
                stop_sequence = int(row["stop_sequence"]),
                arrival_seconds=arrival,
                departure_seconds=departure,
                pickup_type=pickup_type
            )
            by_stop.setdefault(stop_time.stop_id, []).append(stop_time)
    
    for stop_times in by_stop.values():
        stop_times.sort(key=lambda st: st.departure_seconds)

    return by_stop
