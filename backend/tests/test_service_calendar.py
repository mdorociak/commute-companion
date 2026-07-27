from datetime import date
from pathlib import Path

from app.gtfs.service_calendar import load_service_calendar

FIXTURE_DIR = Path(__file__).parent / "fixtures" / "mock_gtfs"

WEDNESDAY = date(2026, 5, 20)
SATURDAY = date(2026, 5, 23)
MONDAY = date(2026, 5, 25)


def test_weekday_service_runs_on_a_weekday() -> None:
    cal = load_service_calendar(FIXTURE_DIR)
    assert cal.runs_on("WEEKDAYS", WEDNESDAY) is True


def test_weekday_service_does_not_run_on_weekend() -> None:
    cal = load_service_calendar(FIXTURE_DIR)
    assert cal.runs_on("WEEKDAYS", SATURDAY) is False


def test_removed_exception_overrides_running_pattern() -> None:
    cal = load_service_calendar(FIXTURE_DIR)
    assert cal.runs_on("WEEKDAYS", MONDAY) is False


def test_weekend_service_runs_on_saturday() -> None:
    cal = load_service_calendar(FIXTURE_DIR)
    assert cal.runs_on("WEEKEND", SATURDAY) is True


def test_service_outside_its_date_window_does_not_run() -> None:
    cal = load_service_calendar(FIXTURE_DIR)
    assert cal.runs_on("EXPIRED", WEDNESDAY) is False


def test_added_exception_runs_service_with_no_weekly_pattern() -> None:
    cal = load_service_calendar(FIXTURE_DIR)
    assert cal.runs_on("HOLIDAY_ONLY", MONDAY) is True


def test_added_exception_service_does_not_run_on_other_dates() -> None:
    cal = load_service_calendar(FIXTURE_DIR)
    assert cal.runs_on("HOLIDAY_ONLY", WEDNESDAY) is False


def test_unknown_service_does_not_run() -> None:
    cal = load_service_calendar(FIXTURE_DIR)
    assert cal.runs_on("NONEXISTENT", WEDNESDAY) is False