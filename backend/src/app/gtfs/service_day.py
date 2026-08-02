from dataclasses import dataclass
from datetime import UTC, date, datetime, time, timedelta
from math import ceil
from zoneinfo import ZoneInfo


@dataclass(frozen=True)
class QueryWindow:
    """A normalized, half-open UTC interval."""

    start_utc: datetime
    end_utc: datetime

    def __post_init__(self) -> None:
        if not _is_aware(self.start_utc) or not _is_aware(self.end_utc):
            raise ValueError("query window boundaries must be timezone-aware")

        start_utc = self.start_utc.astimezone(UTC)
        end_utc = self.end_utc.astimezone(UTC)
        if end_utc <= start_utc:
            raise ValueError("query window end must be after its start")

        object.__setattr__(self, "start_utc", start_utc)
        object.__setattr__(self, "end_utc", end_utc)


@dataclass(frozen=True)
class ServiceDayResolver:
    provider_timezone: ZoneInfo

    def anchor_utc(self, service_date: date) -> datetime:
        local_noon = datetime.combine(
            service_date,
            time(hour=12),
            tzinfo=self.provider_timezone,
        )
        return local_noon.astimezone(UTC) - timedelta(hours=12)

    def scheduled_instant_utc(
        self,
        service_date: date,
        service_day_seconds: int,
    ) -> datetime:
        if service_day_seconds < 0:
            raise ValueError("service-day seconds must not be negative")
        return self.anchor_utc(service_date) + timedelta(seconds=service_day_seconds)

    def candidate_service_dates(
        self,
        window: QueryWindow,
        maximum_service_day_seconds: int,
    ) -> list[date]:
        if maximum_service_day_seconds < 0:
            raise ValueError("maximum service-day seconds must not be negative")

        lookback = max(1, ceil(maximum_service_day_seconds / 86_400))
        first = (
            window.start_utc.astimezone(self.provider_timezone).date()
            - timedelta(days=lookback)
        )
        last = (
            window.end_utc.astimezone(self.provider_timezone).date()
            + timedelta(days=1)
        )
        return [
            first + timedelta(days=offset)
            for offset in range((last - first).days + 1)
        ]


def _is_aware(value: datetime) -> bool:
    return value.tzinfo is not None and value.utcoffset() is not None
