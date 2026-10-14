from pathlib import Path

import pytest

from app.gtfs.loader import load_routes, load_stations, load_trips

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"


def test_load_stations_returns_only_stations_not_platforms() -> None:
    stations = load_stations(FIXTURE_DIR)
    assert len(stations) == 4
    assert "2246799" in stations
    assert "1413092" in stations
    assert "2333170" not in stations


def test_brzeg_has_one_platform_with_correct_code() -> None:
    brzeg = load_stations(FIXTURE_DIR)["2246799"]
    assert brzeg.name == "Brzeg"
    assert brzeg.code == "11"
    assert len(brzeg.platforms) == 1
    assert brzeg.platforms[0].code == "II"


def test_platform_with_blank_code_keeps_code_as_none() -> None:
    brzeg_dolny = load_stations(FIXTURE_DIR)["1413092"]
    codes = [p.code for p in brzeg_dolny.platforms]
    assert None in codes
    assert "II" in codes


def test_station_with_no_platforms_has_empty_list() -> None:
    empty = load_stations(FIXTURE_DIR)["9999999"]
    assert empty.platforms == []


def test_orphan_platform_pointing_at_nonexistent_parent_is_dropped() -> None:
    stations = load_stations(FIXTURE_DIR)
    all_platform_ids = [p.id for s in stations.values() for p in s.platforms]
    assert "8888888" not in all_platform_ids


def test_load_routes_returns_routes_by_id() -> None:
    routes = load_routes(FIXTURE_DIR)
    assert len(routes) == 2
    assert routes["249524"].short_name == "D1"
    assert routes["249497"].short_name == "D7"


def test_load_trips_returns_trips_by_id() -> None:
    trips = load_trips(FIXTURE_DIR)
    assert len(trips) == 5
    trip = trips["38645733_409036"]
    assert trip.route_id == "249497"
    assert trip.service_id == "WEEKDAYS"
    assert trip.headsign == "Sędzisław"


def test_trip_with_blank_headsign_is_none() -> None:
    trips = load_trips(FIXTURE_DIR)
    assert trips["22222222_409037"].headsign is None


def test_every_trip_references_a_known_route() -> None:
    routes = load_routes(FIXTURE_DIR)
    trips = load_trips(FIXTURE_DIR)
    for trip in trips.values():
        assert trip.route_id in routes


@pytest.mark.parametrize(
    ("raw", "expected"), [("   ", None), (" Wrocław Główny ", "Wrocław Główny")]
)
def test_trip_headsign_is_trimmed_and_blank_is_none(
    tmp_path: Path, raw: str, expected: str | None
) -> None:
    _write_trips(tmp_path, headsign=raw)
    assert load_trips(tmp_path)["T1"].headsign == expected


@pytest.mark.parametrize(("raw", "expected"), [("   ", None), (" II ", "II")])
def test_platform_code_is_trimmed_and_blank_is_none(
    tmp_path: Path, raw: str, expected: str | None
) -> None:
    _write_stops(tmp_path, station_code="11", platform_code=raw)
    assert load_stations(tmp_path)["S1"].platforms[0].code == expected


@pytest.mark.parametrize(("raw", "expected"), [("   ", None), (" 11 ", "11")])
def test_station_code_is_trimmed_and_blank_is_none(
    tmp_path: Path, raw: str, expected: str | None
) -> None:
    _write_stops(tmp_path, station_code=raw, platform_code="II")
    assert load_stations(tmp_path)["S1"].code == expected


def _write_trips(directory: Path, *, headsign: str) -> None:
    (directory / "trips.txt").write_text(
        "route_id,service_id,trip_id,trip_headsign\n"
        f'R1,WEEKDAYS,T1,"{headsign}"\n',
        encoding="utf-8",
    )


def _write_stops(directory: Path, *, station_code: str, platform_code: str) -> None:
    (directory / "stops.txt").write_text(
        "stop_id,stop_code,stop_name,stop_lat,stop_lon,"
        "location_type,parent_station,platform_code\n"
        f'S1,"{station_code}",Brzeg,50.85,17.47,1,,\n'
        f'P1,,Brzeg,50.85,17.47,0,S1,"{platform_code}"\n',
        encoding="utf-8",
    )
