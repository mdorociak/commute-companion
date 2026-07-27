import csv
from dataclasses import dataclass
from datetime import date, datetime
from enum import IntEnum
from pathlib import Path

from .models import ServicePattern

class ServiceException(IntEnum):
    ADDED = 1
    REMOVED = 2

def _parse_gtfs_date(value: str) -> date:
    return datetime.strptime(value.strip(), "%Y%m%d").date()

@dataclass
class ServiceCalendar:
    patterns: dict[str, ServicePattern]
    exceptions: dict[tuple[str, date], ServiceException]

    def runs_on(self, service_id: str, on_date: date) -> bool:
        exception = self.exceptions.get((service_id, on_date))
        if exception == ServiceException.REMOVED:
            return False
        if exception == ServiceException.ADDED:
            return True
        
        pattern = self.patterns.get(service_id)
        if pattern is None:
            return False
        if not (pattern.start_date <= on_date <= pattern.end_date):
            return False
        return pattern.weekdays[on_date.weekday()]
    
def load_service_calendar(gtfs_dir: Path) -> ServiceCalendar:
    patterns: dict[str, ServicePattern] = {}
    calendar_file = gtfs_dir / "calendar.txt"
    if calendar_file.exists():
        with calendar_file.open(encoding="utf-8") as f:
            for row in csv.DictReader(f):
                patterns[row["service_id"]] = ServicePattern(
                    service_id=row["service_id"],
                    weekdays=(
                        row["monday"] == "1",
                        row["tuesday"] == "1",
                        row["wednesday"] == "1",
                        row["thursday"] == "1",
                        row["friday"] == "1",
                        row["saturday"] == "1",
                        row["sunday"] == "1"
                    ),
                    start_date=_parse_gtfs_date(row["start_date"]),
                    end_date=_parse_gtfs_date(row["end_date"])
                )
    exceptions: dict[tuple[str, date], ServiceException] = {}
    exceptions_file = gtfs_dir / "calendar_dates.txt"
    if exceptions_file.exists():
        with exceptions_file.open(encoding="utf-8") as f:
            for row in csv.DictReader(f):
                key = (row["service_id"], _parse_gtfs_date(row["date"]))
                exceptions[key] = ServiceException(int(row["exception_type"]))
    return ServiceCalendar(patterns=patterns, exceptions=exceptions)
