"""Builds a deterministic GTFS-RT .pb fixture for tests.

Unlike the static GTFS fixture (a directory of CSVs we hand-edit), the RT
fixture is a binary file — but we don't want to commit opaque bytes that
nobody can read or modify. So we build it from this script at test time:
the script IS the fixture's source of truth.

Scenario this encodes:
  - One trip (TRIP_A) with two predicted stops: sequence 2 on time,
    sequence 5 delayed by 4 minutes vs its scheduled 18:39.
  - One vehicle at a real coordinate.
  - One vehicle not reporting (lat/lon = 0) — mirrors KD's real behavior.
  - A malformed trip_update missing trip_id, to test defensive parsing.
"""
from pathlib import Path
from google.transit import gtfs_realtime_pb2


def build_fixture(path: Path) -> None:
    feed = gtfs_realtime_pb2.FeedMessage()
    feed.header.gtfs_realtime_version = "2.0"
    feed.header.incrementality = gtfs_realtime_pb2.FeedHeader.FULL_DATASET
    feed.header.timestamp = 1_780_855_700

    # Trip with two stop predictions.
    e1 = feed.entity.add()
    e1.id = "t-TRIP_A"
    e1.trip_update.trip.trip_id = "TRIP_A"
    e1.trip_update.vehicle.id = "V_100"
    s1 = e1.trip_update.stop_time_update.add()
    s1.stop_sequence = 2
    s1.arrival.time = 1_780_855_498
    s1.departure.time = 1_780_855_498
    s2 = e1.trip_update.stop_time_update.add()
    s2.stop_sequence = 5
    s2.arrival.time = 1_780_856_518
    s2.departure.time = 1_780_856_518

    # Reporting vehicle.
    e2 = feed.entity.add()
    e2.id = "v-V_100"
    e2.vehicle.vehicle.id = "V_100"
    e2.vehicle.position.latitude = 50.852881
    e2.vehicle.position.longitude = 17.470911
    e2.vehicle.timestamp = 1_780_855_666

    # Non-reporting vehicle (lat/lon = 0).
    e3 = feed.entity.add()
    e3.id = "v-V_200"
    e3.vehicle.vehicle.id = "V_200"
    e3.vehicle.timestamp = 1_780_855_666

    e4 = feed.entity.add()
    e4.id = "t-malformed"
    e4.trip_update.trip.trip_id = ""   
    e4.trip_update.stop_time_update.add().stop_sequence = 1

    path.write_bytes(feed.SerializeToString())


if __name__ == "__main__":
    out = Path(__file__).parent / "rt_sample.pb"
    build_fixture(out)
    print(f"Wrote {out}")