import argparse
import csv
import hashlib
import statistics
import tempfile
import zipfile
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass
from datetime import UTC, date, datetime, timedelta
from itertools import pairwise
from math import ceil
from pathlib import Path
from zoneinfo import ZoneInfo

from google.transit import gtfs_realtime_pb2

from app.gtfs.loader import load_feed_info, load_trips
from app.gtfs.models import FeedInfo, Trip
from app.gtfs.service_calendar import ServiceCalendar, load_service_calendar
from app.gtfs.service_day import ServiceDayResolver
from app.gtfs.stop_times import StopTime, load_stop_times
from app.gtfs_rt.parser import parse_feed

BACKEND = Path(__file__).resolve().parents[1]
DEFAULT_CAPTURES = BACKEND / "data" / "kd_rt"
DEFAULT_GTFS = BACKEND / "data" / "kd_gtfs"
WARSAW = ZoneInfo("Europe/Warsaw")
SEARCH_DAYS = range(-3, 3)
TRIP_FIELDS = ("start_date", "start_time", "route_id", "direction_id")
TRIP_UPDATE_FIELDS = ("timestamp", "delay")
EVENT_FIELDS = ("time", "delay", "uncertainty")
STATIC_FILES = (
    "stop_times.txt",
    "trips.txt",
    "calendar.txt",
    "calendar_dates.txt",
    "feed_info.txt",
)

_TripRelationship = gtfs_realtime_pb2.TripDescriptor.ScheduleRelationship
_StopRelationship = gtfs_realtime_pb2.TripUpdate.StopTimeUpdate.ScheduleRelationship
_Incrementality = gtfs_realtime_pb2.FeedHeader.Incrementality
_VehicleStopStatus = gtfs_realtime_pb2.VehiclePosition.VehicleStopStatus
_TripUpdate = gtfs_realtime_pb2.TripUpdate
_VehiclePosition = gtfs_realtime_pb2.VehiclePosition


@dataclass(frozen=True)
class Capture:
    acquired_at: datetime
    last_modified: str
    body: bytes
    feed: gtfs_realtime_pb2.FeedMessage


@dataclass(frozen=True)
class Static:
    feed_info: FeedInfo | None
    trips: dict[str, Trip]
    calendar: ServiceCalendar
    stops_by_trip: dict[str, dict[int, StopTime]]


@dataclass(frozen=True)
class StopEvent:
    delay: float
    service_date: date
    scheduled: datetime
    predicted: datetime
    departure_seconds: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Summarize captured KD GTFS-Realtime snapshots against a static "
            "export: the open values and the feed assumptions of ADR-0008."
        ),
    )
    parser.add_argument(
        "captures",
        type=Path,
        nargs="?",
        default=DEFAULT_CAPTURES,
        help="directory holding captures.csv and the .pb files",
    )
    parser.add_argument(
        "--gtfs",
        type=Path,
        default=DEFAULT_GTFS,
        help="static export, as a directory or a .zip",
    )
    return parser.parse_args()


def load_captures(directory: Path) -> tuple[list[Capture], Counter[str]]:
    index_path = directory / "captures.csv"
    if not index_path.exists():
        raise SystemExit(f"no captures.csv in {directory}")
    captures: list[Capture] = []
    failures: Counter[str] = Counter()
    with index_path.open(encoding="utf-8", newline="") as index:
        for row in csv.DictReader(index):
            if row["error"] or not row["file"]:
                failures[row["error"] or "no file"] += 1
                continue
            path = directory / row["file"]
            if not path.exists():
                failures["file missing"] += 1
                continue
            body = path.read_bytes()
            feed = gtfs_realtime_pb2.FeedMessage()
            feed.ParseFromString(body)
            captures.append(
                Capture(
                    acquired_at=datetime.fromisoformat(row["acquired_at"]),
                    last_modified=row["last_modified"],
                    body=body,
                    feed=feed,
                )
            )
    captures.sort(key=lambda capture: capture.acquired_at)
    return captures, failures


def load_static(path: Path) -> Static:
    with tempfile.TemporaryDirectory() as scratch:
        directory = path
        if path.suffix == ".zip":
            with zipfile.ZipFile(path) as archive:
                for name in STATIC_FILES:
                    if name in archive.namelist():
                        archive.extract(name, scratch)
            directory = Path(scratch)
        if not (directory / "stop_times.txt").exists():
            raise SystemExit(f"no stop_times.txt in {path}")
        stops_by_trip: dict[str, dict[int, StopTime]] = {}
        for stop_times in load_stop_times(directory).values():
            for stop_time in stop_times:
                stops = stops_by_trip.setdefault(stop_time.trip_id, {})
                stops[stop_time.stop_sequence] = stop_time
        feed_info_path = directory / "feed_info.txt"
        return Static(
            feed_info=load_feed_info(directory) if feed_info_path.exists() else None,
            trips=load_trips(directory),
            calendar=load_service_calendar(directory),
            stops_by_trip=stops_by_trip,
        )


def trip_updates(feed: gtfs_realtime_pb2.FeedMessage) -> list[_TripUpdate]:
    return [
        entity.trip_update
        for entity in feed.entity
        if entity.HasField("trip_update")
    ]


def header_instant(feed: gtfs_realtime_pb2.FeedMessage) -> datetime | None:
    if not feed.header.HasField("timestamp"):
        return None
    return datetime.fromtimestamp(feed.header.timestamp, tz=UTC)


def trip_update_digest(feed: gtfs_realtime_pb2.FeedMessage) -> str:
    parts = sorted(
        entity.SerializeToString(deterministic=True)
        for entity in feed.entity
        if entity.HasField("trip_update")
    )
    return hashlib.sha256(b"".join(parts)).hexdigest()


def report_captures(captures: list[Capture], failures: Counter[str]) -> None:
    failed = sum(failures.values())
    print(f"Captures: {len(captures) + failed} rows, {len(captures)} parsed, "
          f"{failed} failed")
    first, last = captures[0].acquired_at, captures[-1].acquired_at
    print(f"  span {local(first)} to {local(last)} "
          f"({duration((last - first).total_seconds())})")
    gaps = [
        ((later.acquired_at - earlier.acquired_at).total_seconds(), earlier)
        for earlier, later in pairwise(captures)
    ]
    if gaps:
        largest, before = max(gaps, key=lambda gap: gap[0])
        median = statistics.median(gap for gap, _ in gaps)
        print(f"  interval median {duration(median)}, largest gap "
              f"{duration(largest)} after {local(before.acquired_at)}")
    for error, count in failures.most_common():
        print(f"  failed {count}x: {error}")


def report_freshness(captures: list[Capture]) -> None:
    print("\nFreshness")
    headers = [header_instant(capture.feed) for capture in captures]
    lags = [
        (capture.acquired_at - header).total_seconds()
        for capture, header in zip(captures, headers, strict=True)
        if header is not None
    ]
    missing = len(captures) - len(lags)
    print(f"  acquisition minus header timestamp: {summary(lags)}"
          + (f"; {missing} snapshots without one" if missing else ""))

    ages = [
        (header - datetime.fromtimestamp(entity.vehicle.timestamp, tz=UTC))
        .total_seconds()
        for capture, header in zip(captures, headers, strict=True)
        if header is not None
        for entity in capture.feed.entity
        if entity.HasField("vehicle") and entity.vehicle.HasField("timestamp")
    ]
    print(f"  vehicle position age at the header: {summary(ages)}")

    pairs = list(pairwise(zip(captures, headers, strict=True)))
    if not pairs:
        print("  one snapshot: nothing to compare between captures")
        return
    advanced = sum(
        1
        for (_, earlier), (_, later) in pairs
        if earlier is not None and later is not None and later > earlier
    )
    print(f"  header advanced on {advanced} of {len(pairs)} consecutive pairs")

    digests = [trip_update_digest(capture.feed) for capture in captures]
    report_changes(
        "trip updates",
        [capture.acquired_at for capture in captures],
        digests,
    )
    if any(capture.last_modified for capture in captures):
        report_changes(
            "Last-Modified",
            [capture.acquired_at for capture in captures],
            [capture.last_modified for capture in captures],
        )
    else:
        print("  Last-Modified: never sent")


def report_changes(label: str, instants: list[datetime], values: list[str]) -> None:
    changed_at = [
        later_at
        for (_, earlier), (later_at, later) in pairwise(
            zip(instants, values, strict=True)
        )
        if earlier != later
    ]
    intervals = [
        (later - earlier).total_seconds() for earlier, later in pairwise(changed_at)
    ]
    print(f"  {label} changed on {len(changed_at)} of {len(values) - 1} "
          f"consecutive pairs; interval between changes: {summary(intervals)}")


def report_shape(captures: list[Capture]) -> None:
    print("\nFeed shape")
    incrementality = Counter(
        enum_name(_Incrementality, capture.feed.header.incrementality)
        for capture in captures
    )
    print(f"  incrementality: {counts(incrementality)}")
    for kind in ("trip_update", "vehicle", "alert"):
        per_snapshot = [
            sum(1 for entity in capture.feed.entity if entity.HasField(kind))
            for capture in captures
        ]
        print(f"  {kind} per snapshot: {summary(per_snapshot, number)}")

    fields: Counter[str] = Counter()
    trip_relationships: Counter[str] = Counter()
    stop_relationships: Counter[str] = Counter()
    update_count = stop_count = repeated = 0
    for capture in captures:
        updates = trip_updates(capture.feed)
        trip_ids = [update.trip.trip_id for update in updates]
        if len(trip_ids) != len(set(trip_ids)):
            repeated += 1
        for update in updates:
            update_count += 1
            for field in TRIP_FIELDS:
                fields[f"trip.{field}"] += update.trip.HasField(field)
            for field in TRIP_UPDATE_FIELDS:
                fields[field] += update.HasField(field)
            trip_relationships[
                enum_name(_TripRelationship, update.trip.schedule_relationship)
            ] += 1
            for stop in update.stop_time_update:
                stop_count += 1
                fields["stop_id"] += stop.HasField("stop_id")
                for event in ("arrival", "departure"):
                    for field in EVENT_FIELDS:
                        fields[f"{event}.{field}"] += stop.HasField(
                            event
                        ) and getattr(stop, event).HasField(field)
                stop_relationships[
                    enum_name(_StopRelationship, stop.schedule_relationship)
                ] += 1

    print(f"  {update_count} trip updates across all snapshots; fields sent: "
          + ", ".join(
              f"{name} {fields[name]}"
              for name in (
                  *(f"trip.{field}" for field in TRIP_FIELDS),
                  *TRIP_UPDATE_FIELDS,
              )
          ))
    print(f"  trip relationships: {counts(trip_relationships)}")
    print(f"  {stop_count} stop time updates; fields sent: "
          + ", ".join(
              f"{name} {fields[name]}"
              for name in (
                  "stop_id",
                  *(f"{event}.{field}" for event in ("arrival", "departure")
                    for field in EVENT_FIELDS),
              )
          ))
    print(f"  stop relationships: {counts(stop_relationships)}")
    print(f"  snapshots repeating a trip ID: {repeated}")
    rejections = Counter(
        rejection.reason.value
        for capture in captures
        for rejection in parse_feed(capture.body).rejections
    )
    print(f"  parser rejections: {counts(rejections) or 'none'}")


def report_static(captures: list[Capture], static: Static, source: Path) -> None:
    validity = ""
    if static.feed_info is not None:
        validity = (f" (feed {static.feed_info.start_date} to "
                    f"{static.feed_info.end_date})")
    print(f"\nAgainst {source}{validity}")

    found = total = 0
    lowest: tuple[int, int] | None = None
    unknown_trips: set[str] = set()
    unknown_sequences = stop_id_disagreements = 0
    layouts: Counter[str] = Counter()
    starts: Counter[str] = Counter()
    final_only_ages: list[float] = []
    for capture in captures:
        updates = trip_updates(capture.feed)
        known = [u for u in updates if u.trip.trip_id in static.stops_by_trip]
        unknown_trips.update(u.trip.trip_id for u in updates)
        unknown_trips.difference_update(static.stops_by_trip)
        found += len(known)
        total += len(updates)
        if updates and (
            lowest is None or len(known) * lowest[1] < lowest[0] * len(updates)
        ):
            lowest = (len(known), len(updates))
        by_trip, by_vehicle = vehicles(capture.feed)

        for update in known:
            stops = static.stops_by_trip[update.trip.trip_id]
            sequences = sorted({stop.stop_sequence for stop in update.stop_time_update})
            if not sequences:
                layouts["no stops"] += 1
                continue
            for stop in update.stop_time_update:
                if stop.stop_sequence not in stops:
                    unknown_sequences += 1
                elif stop.HasField("stop_id") and (
                    stop.stop_id != stops[stop.stop_sequence].stop_id
                ):
                    stop_id_disagreements += 1
            layouts[layout(sequences, sorted(stops))] += 1

            vehicle = by_trip.get(update.trip.trip_id)
            if vehicle is None and update.HasField("vehicle"):
                vehicle = by_vehicle.get(update.vehicle.id)
            starts[start_against_vehicle(sequences[0], vehicle)] += 1

            if len(sequences) == 1 and sequences[0] == max(stops):
                event = update.stop_time_update[0]
                has_departure = event.departure.HasField("time")
                at = event.departure if has_departure else event.arrival
                if at.HasField("time"):
                    predicted = datetime.fromtimestamp(at.time, tz=UTC)
                    final_only_ages.append(
                        (capture.acquired_at - predicted).total_seconds()
                    )

    lowest_text = f"{lowest[0]} of {lowest[1]}" if lowest else "none"
    print(f"  trip IDs found: {found} of {total} trip updates; lowest in one "
          f"snapshot {lowest_text}; {len(unknown_trips)} distinct IDs missing")
    print(f"  stop sequences not in their trip: {unknown_sequences}; "
          f"stop IDs disagreeing at their sequence: {stop_id_disagreements}")
    print(f"  stops listed, from the lowest sequence: {counts(layouts)}")
    print(f"  lowest sequence against the vehicle: {counts(starts)}")
    print(f"  updates holding only the final stop: {len(final_only_ages)}; "
          f"time before acquisition: {summary(final_only_ages)}")


def layout(sequences: list[int], trip_sequences: list[int]) -> str:
    if any(sequence not in trip_sequences for sequence in sequences):
        return "sequence not in the trip"
    expected = [sequence for sequence in trip_sequences if sequence >= sequences[0]]
    if sequences == expected:
        return "every stop to the end"
    if sequences[-1] == expected[-1]:
        return "to the end with a gap"
    return "stops before the end"


def vehicles(
    feed: gtfs_realtime_pb2.FeedMessage,
) -> tuple[dict[str, _VehiclePosition], dict[str, _VehiclePosition]]:
    by_trip: dict[str, _VehiclePosition] = {}
    by_vehicle: dict[str, _VehiclePosition] = {}
    for entity in feed.entity:
        if not entity.HasField("vehicle"):
            continue
        vehicle = entity.vehicle
        if vehicle.HasField("trip") and vehicle.trip.trip_id:
            by_trip[vehicle.trip.trip_id] = vehicle
        if vehicle.HasField("vehicle") and vehicle.vehicle.id:
            by_vehicle[vehicle.vehicle.id] = vehicle
    return by_trip, by_vehicle


def start_against_vehicle(
    first_sequence: int, vehicle: _VehiclePosition | None
) -> str:
    if vehicle is None:
        return "no vehicle"
    if not vehicle.HasField("current_stop_sequence"):
        return "vehicle without a current stop"
    status = (
        enum_name(_VehicleStopStatus, vehicle.current_status)
        if vehicle.HasField("current_status")
        else "no status"
    )
    current = vehicle.current_stop_sequence
    if first_sequence == current:
        return f"equal {status}"
    if first_sequence > current:
        return f"later {status}"
    return f"earlier {status}"


def report_delays(captures: list[Capture], static: Static) -> None:
    print("\nDepartures, each stop event at the largest delay predicted for it")
    resolver = ServiceDayResolver(WARSAW)
    events: dict[tuple[str, date, int], StopEvent] = {}
    next_runs: list[float] = []
    unresolved = 0
    for capture in captures:
        for update in trip_updates(capture.feed):
            trip = static.trips.get(update.trip.trip_id)
            stops = static.stops_by_trip.get(update.trip.trip_id)
            if trip is None or stops is None:
                continue
            for stop in update.stop_time_update:
                scheduled_stop = stops.get(stop.stop_sequence)
                if scheduled_stop is None or not (
                    stop.HasField("departure") and stop.departure.HasField("time")
                ):
                    continue
                predicted = datetime.fromtimestamp(stop.departure.time, tz=UTC)
                runs = runs_near(
                    predicted, trip, scheduled_stop, static.calendar, resolver
                )
                if not runs:
                    unresolved += 1
                    continue
                if len(runs) > 1:
                    next_runs.append(abs((predicted - runs[1][1]).total_seconds()))
                service_date, scheduled = runs[0]
                delay = (predicted - scheduled).total_seconds()
                key = (update.trip.trip_id, service_date, stop.stop_sequence)
                if key not in events or delay > events[key].delay:
                    events[key] = StopEvent(
                        delay=delay,
                        service_date=service_date,
                        scheduled=scheduled,
                        predicted=predicted,
                        departure_seconds=scheduled_stop.departure_seconds,
                    )

    print(f"  delay: {summary([event.delay for event in events.values()])}")
    largest = sorted(events.items(), key=lambda item: item[1].delay, reverse=True)
    for (trip_id, _, sequence), event in largest[:5]:
        print(f"    {duration(event.delay):>12}  trip {trip_id} seq {sequence}, "
              f"service date {event.service_date}, scheduled "
              f"{local(event.scheduled)}, predicted {local(event.predicted)}")

    by_hour: dict[datetime, list[float]] = {}
    for event in events.values():
        hour = event.scheduled.astimezone(WARSAW).replace(
            minute=0, second=0, microsecond=0
        )
        by_hour.setdefault(hour, []).append(event.delay)
    print("  by scheduled hour:")
    for hour, delays in sorted(by_hour.items()):
        print(f"    {hour:%a %H}:00  {len(delays):>4} events, median "
              f"{duration(statistics.median(delays))}, max {duration(max(delays))}")

    closest = duration(min(next_runs)) if next_runs else "none within the search"
    print(f"  closest other run of the same trip to a prediction: {closest}")
    print(f"  stop updates with no run within {SEARCH_DAYS.start} to "
          f"{SEARCH_DAYS.stop - 1} days of their prediction: {unresolved}")

    crossings: Counter[str] = Counter()
    for event in events.values():
        if event.service_date == event.predicted.astimezone(WARSAW).date():
            continue
        if event.departure_seconds >= 86_400:
            crossings["scheduled past 24:00"] += 1
        elif event.predicted.astimezone(WARSAW).date() > event.service_date:
            crossings["predicted past midnight"] += 1
        else:
            crossings["other"] += 1
    print(f"  service date differs from the predicted civil date: "
          f"{sum(crossings.values())} of {len(events)} events"
          + (f" ({counts(crossings)})" if crossings else ""))


def runs_near(
    predicted: datetime,
    trip: Trip,
    stop: StopTime,
    calendar: ServiceCalendar,
    resolver: ServiceDayResolver,
) -> list[tuple[date, datetime]]:
    predicted_day = predicted.astimezone(WARSAW).date()
    runs = []
    for offset in SEARCH_DAYS:
        service_date = predicted_day + timedelta(days=offset)
        if calendar.runs_on(trip.service_id, service_date):
            scheduled = resolver.scheduled_instant_utc(
                service_date, stop.departure_seconds
            )
            runs.append((service_date, scheduled))
    return sorted(runs, key=lambda run: abs((predicted - run[1]).total_seconds()))


def enum_name(enum, value: int) -> str:
    try:
        return enum.Name(value)
    except ValueError:
        return f"unknown {value}"


def counts(counter: Counter[str]) -> str:
    return ", ".join(f"{name} {count}" for name, count in counter.most_common())


def summary(values: list[float], fmt: Callable[[float], str] | None = None) -> str:
    fmt = fmt or duration
    if not values:
        return "none"
    ordered = sorted(values)
    p95 = ordered[max(0, ceil(0.95 * len(ordered)) - 1)]
    return (f"min {fmt(ordered[0])}, median {fmt(statistics.median(ordered))}, "
            f"p95 {fmt(p95)}, max {fmt(ordered[-1])} (n={len(ordered)})")


def number(value: float) -> str:
    return f"{value:g}"


def duration(seconds: float) -> str:
    rounded = round(seconds)
    sign = "-" if rounded < 0 else ""
    hours, remainder = divmod(abs(rounded), 3600)
    minutes, secs = divmod(remainder, 60)
    if hours:
        return f"{sign}{hours} h {minutes:02d} min"
    if minutes:
        return f"{sign}{minutes} min {secs:02d} s"
    return f"{sign}{secs} s"


def local(instant: datetime) -> str:
    return f"{instant.astimezone(WARSAW):%Y-%m-%d %H:%M:%S}"


def main() -> None:
    args = parse_args()
    captures, failures = load_captures(args.captures)
    if not captures:
        raise SystemExit(f"no parsed captures in {args.captures}")
    static = load_static(args.gtfs)
    report_captures(captures, failures)
    report_freshness(captures)
    report_shape(captures)
    report_static(captures, static, args.gtfs)
    report_delays(captures, static)


if __name__ == "__main__":
    main()
