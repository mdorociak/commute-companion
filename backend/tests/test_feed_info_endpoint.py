from datetime import date
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from app.gtfs.loader import load_feed_info
from app.main import app

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"


@pytest.fixture(autouse=True)
def reset_state():
    yield
    app.state.feed_info = None


def test_feed_info_returns_publisher_and_validity_window() -> None:
    app.state.feed_info = load_feed_info(FIXTURE_DIR)
    response = TestClient(app).get("/feed-info")
    assert response.status_code == 200
    body = response.json()
    assert body["publisher_name"] == "kiedyPrzyjedzie.pl"
    assert body["lang"] == "pl"
    assert body["start_date"] == "2026-05-03"
    assert body["end_date"] == "2026-12-12"


def test_feed_info_is_404_when_no_feed_loaded() -> None:
    app.state.feed_info = None
    response = TestClient(app).get("/feed-info")
    assert response.status_code == 404


def test_load_feed_info_parses_dates() -> None:
    feed_info = load_feed_info(FIXTURE_DIR)
    assert feed_info.start_date == date(2026, 5, 3)
    assert feed_info.end_date == date(2026, 12, 12)
    assert feed_info.publisher_url == "http://kiedyprzyjedzie.pl"