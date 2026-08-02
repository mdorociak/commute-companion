from datetime import UTC, date, datetime
from zoneinfo import ZoneInfo

import pytest

from app.gtfs.service_day import QueryWindow, ServiceDayResolver


WARSAW = ZoneInfo("Europe/Warsaw")
RESOLVER = ServiceDayResolver(WARSAW)


def test_query_window_normalizes_bounds_to_utc() -> None:
    window = QueryWindow(
        datetime(2026, 5, 24, 0, 30, tzinfo=WARSAW),
        datetime(2026, 5, 24, 2, 0, tzinfo=WARSAW),
    )

    assert window.start_utc == datetime(2026, 5, 23, 22, 30, tzinfo=UTC)
    assert window.end_utc == datetime(2026, 5, 24, 0, 0, tzinfo=UTC)
    assert window.start_utc.tzinfo is UTC
    assert window.end_utc.tzinfo is UTC


@pytest.mark.parametrize(
    ("start", "end"),
    [
        (datetime(2026, 5, 24, 0, 30), datetime(2026, 5, 24, 2, 0, tzinfo=UTC)),
        (datetime(2026, 5, 24, 0, 30, tzinfo=UTC), datetime(2026, 5, 24, 2, 0)),
        (datetime(2026, 5, 24, 2, 0, tzinfo=UTC), datetime(2026, 5, 24, 2, 0, tzinfo=UTC)),
        (datetime(2026, 5, 24, 3, 0, tzinfo=UTC), datetime(2026, 5, 24, 2, 0, tzinfo=UTC)),
    ],
)
def test_query_window_rejects_invalid_boundaries(
    start: datetime,
    end: datetime,
) -> None:
    with pytest.raises(ValueError):
        QueryWindow(start, end)


def test_ordinary_day_resolves_time_beyond_midnight() -> None:
    resolved = RESOLVER.scheduled_instant_utc(
        date(2026, 5, 23),
        25 * 3600 + 10 * 60,
    )

    assert resolved == datetime(2026, 5, 23, 23, 10, tzinfo=UTC)
    assert resolved.astimezone(WARSAW) == datetime(
        2026, 5, 24, 1, 10, tzinfo=WARSAW
    )


def test_spring_dst_anchor_uses_elapsed_time_from_local_noon() -> None:
    assert RESOLVER.anchor_utc(date(2026, 3, 29)) == datetime(
        2026, 3, 28, 22, 0, tzinfo=UTC
    )
    assert RESOLVER.scheduled_instant_utc(
        date(2026, 3, 29), 3 * 3600 + 30 * 60
    ) == datetime(2026, 3, 29, 1, 30, tzinfo=UTC)


def test_autumn_dst_resolution_preserves_the_second_fold() -> None:
    assert RESOLVER.anchor_utc(date(2026, 10, 25)) == datetime(
        2026, 10, 24, 23, 0, tzinfo=UTC
    )

    localized = RESOLVER.scheduled_instant_utc(
        date(2026, 10, 25), 2 * 3600 + 30 * 60
    ).astimezone(WARSAW)
    assert localized == datetime(2026, 10, 25, 2, 30, tzinfo=WARSAW, fold=1)
    assert localized.fold == 1
    assert localized.utcoffset().total_seconds() == 3600


def test_candidate_dates_derive_a_multi_day_lookback_from_feed_maximum() -> None:
    window = QueryWindow(
        datetime(2026, 5, 24, 0, 30, tzinfo=WARSAW),
        datetime(2026, 5, 24, 2, 0, tzinfo=WARSAW),
    )

    assert RESOLVER.candidate_service_dates(window, 49 * 3600) == [
        date(2026, 5, 21),
        date(2026, 5, 22),
        date(2026, 5, 23),
        date(2026, 5, 24),
        date(2026, 5, 25),
    ]


def test_negative_service_day_values_are_rejected() -> None:
    window = QueryWindow(
        datetime(2026, 5, 24, 0, 30, tzinfo=UTC),
        datetime(2026, 5, 24, 2, 0, tzinfo=UTC),
    )
    with pytest.raises(ValueError):
        RESOLVER.scheduled_instant_utc(date(2026, 5, 24), -1)
    with pytest.raises(ValueError):
        RESOLVER.candidate_service_dates(window, -1)
