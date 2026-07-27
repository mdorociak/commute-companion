from pathlib import Path
import pytest

from app.gtfs_rt.parser import parse_feed
from tests.fixtures.mock_gtfs.build_rt_fixture import build_fixture


@pytest.fixture
def rt_bytes(tmp_path: Path) -> bytes:
    pb = tmp_path / "rt_sample.pb"
    build_fixture(pb)
    return pb.read_bytes()


def test_header_timestamp_is_extracted(rt_bytes):
    snapshot = parse_feed(rt_bytes)
    assert snapshot.feed_timestamp == 1_780_855_700


def test_trip_update_is_keyed_by_trip_id_and_stop_sequence(rt_bytes):
    snapshot = parse_feed(rt_bytes)
    assert "TRIP_A" in snapshot.trip_updates
    tu = snapshot.trip_updates["TRIP_A"]
    assert set(tu.stops.keys()) == {2, 5}
    assert tu.stops[2].departure_time == 1_780_855_498
    assert tu.stops[5].departure_time == 1_780_856_518
    assert tu.vehicle_id == "V_100"


def test_malformed_trip_update_is_dropped(rt_bytes):
    snapshot = parse_feed(rt_bytes)
    assert len(snapshot.trip_updates) == 1   # only TRIP_A, not the malformed one


def test_vehicle_positions_include_non_reporting(rt_bytes):
    snapshot = parse_feed(rt_bytes)
    ids = {v.vehicle_id for v in snapshot.vehicle_positions}
    assert ids == {"V_100", "V_200"}
    reporting = next(v for v in snapshot.vehicle_positions if v.vehicle_id == "V_100")
    assert reporting.latitude == pytest.approx(50.852881)
    assert reporting.longitude == pytest.approx(17.470911)


def test_combined_feed_routes_entities_by_type(rt_bytes):
    snapshot = parse_feed(rt_bytes)
    assert len(snapshot.trip_updates) == 1
    assert len(snapshot.vehicle_positions) == 2