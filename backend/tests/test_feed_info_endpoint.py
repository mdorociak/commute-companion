from datetime import date
from pathlib import Path

from fastapi.testclient import TestClient

from app.gtfs.loader import load_feed_info
from app.main import app

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"


def test_feed_info_route_is_not_exposed_as_a_public_v1_resource() -> None:
    response = TestClient(app).get("/feed-info")
    assert response.status_code == 404


def test_load_feed_info_parses_dates() -> None:
    feed_info = load_feed_info(FIXTURE_DIR)
    assert feed_info.start_date == date(2026, 5, 3)
    assert feed_info.end_date == date(2026, 12, 12)
    assert feed_info.publisher_url == "http://kiedyprzyjedzie.pl"
