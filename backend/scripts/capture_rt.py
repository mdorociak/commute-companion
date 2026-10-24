import argparse
import base64
import csv
import hashlib
import netrc
import os
import sys
import time
from datetime import UTC, datetime
from http.client import HTTPException
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

from google.protobuf.message import DecodeError
from google.transit import gtfs_realtime_pb2

DEFAULT_OUT = Path(__file__).resolve().parents[1] / "data" / "kd_rt"
MAX_BYTES = 20 * 1024 * 1024
INDEX_FIELDS = (
    "acquired_at",
    "elapsed_ms",
    "status",
    "bytes",
    "sha256",
    "header_timestamp",
    "entities",
    "last_modified",
    "server_date",
    "file",
    "error",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Download the KD GTFS-Realtime feed on an interval. The link comes "
            "from KD_RT_URL, the login and password from the ~/.netrc entry "
            "for its host."
        ),
    )
    duration = parser.add_mutually_exclusive_group(required=True)
    duration.add_argument("--once", action="store_true", help="fetch once and stop")
    duration.add_argument("--minutes", type=float, help="keep fetching this long")
    parser.add_argument("--interval", type=float, default=30.0, help="seconds")
    parser.add_argument("--timeout", type=float, default=20.0, help="seconds")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    return parser.parse_args()


def feed_url() -> str:
    url = os.environ.get("KD_RT_URL", "").strip()
    if not url:
        raise SystemExit("KD_RT_URL is not set")
    parts = urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise SystemExit(
            "KD_RT_URL must look like https://host/path; "
            f"parsed scheme {parts.scheme!r}, host {parts.hostname!r}"
        )
    if parts.scheme != "https":
        print("warning: KD_RT_URL is not https; the password travels in clear",
              file=sys.stderr)
    return url


def basic_auth(url: str) -> str:
    host = urlsplit(url).hostname
    if host is None:
        raise SystemExit("KD_RT_URL has no host")
    try:
        entry = netrc.netrc().authenticators(host)
    except (FileNotFoundError, netrc.NetrcParseError) as error:
        raise SystemExit(f"cannot read ~/.netrc: {error}") from error
    if entry is None:
        raise SystemExit(f"~/.netrc has no entry for {host}")
    login, _, password = entry
    token = base64.b64encode(f"{login}:{password}".encode()).decode("ascii")
    return f"Basic {token}"


def capture(url: str, auth: str, out: Path, timeout: float) -> dict[str, object]:
    acquired_at = datetime.now(UTC)
    row: dict[str, object] = {
        "acquired_at": acquired_at.isoformat(timespec="milliseconds"),
    }
    request = Request(url)
    request.add_unredirected_header("Authorization", auth)
    started = time.monotonic()
    try:
        with urlopen(request, timeout=timeout) as response:
            body = response.read(MAX_BYTES + 1)
            row["status"] = response.status
            row["last_modified"] = response.headers.get("Last-Modified", "")
            row["server_date"] = response.headers.get("Date", "")
    except HTTPError as error:
        row["status"] = error.code
        row["error"] = f"HTTP {error.code} {error.reason}"
        return row
    except (URLError, OSError, HTTPException) as error:
        row["error"] = str(getattr(error, "reason", error))
        return row
    finally:
        row["elapsed_ms"] = round((time.monotonic() - started) * 1000)

    row["bytes"] = len(body)
    if len(body) > MAX_BYTES:
        row["error"] = f"body larger than {MAX_BYTES} bytes"
        return row
    row["sha256"] = hashlib.sha256(body).hexdigest()

    stem = acquired_at.strftime("%Y%m%dT%H%M%S.%f")[:-3] + "Z"
    feed = gtfs_realtime_pb2.FeedMessage()
    try:
        feed.ParseFromString(body)
    except DecodeError:
        name = f"{stem}.invalid"
        row["error"] = "body is not a GTFS-Realtime feed"
    else:
        name = f"{stem}.pb"
        row["header_timestamp"] = feed.header.timestamp
        row["entities"] = len(feed.entity)

    partial = out / f"{name}.part"
    partial.write_bytes(body)
    partial.replace(out / name)
    row["file"] = name
    return row


def main() -> None:
    args = parse_args()
    if args.interval <= 0:
        raise SystemExit("--interval must be positive")
    url = feed_url()
    auth = basic_auth(url)
    args.out.mkdir(parents=True, exist_ok=True)
    index_path = args.out / "captures.csv"
    write_header = not index_path.exists()
    deadline = None if args.once else time.monotonic() + args.minutes * 60

    captured = failed = 0
    with index_path.open("a", newline="", encoding="utf-8") as index:
        writer = csv.DictWriter(index, INDEX_FIELDS)
        if write_header:
            writer.writeheader()
        next_at = time.monotonic()
        try:
            while True:
                row = capture(url, auth, args.out, args.timeout)
                writer.writerow(row)
                index.flush()
                if row.get("error"):
                    failed += 1
                    print(f"{row['acquired_at']} {row['error']}", file=sys.stderr)
                else:
                    captured += 1
                    print(f"{row['acquired_at']} {row['bytes']} B, "
                          f"header {row['header_timestamp']}, "
                          f"{row['entities']} entities")
                if row.get("status") in (401, 403):
                    raise SystemExit(
                        "the feed refused access; check the ~/.netrc entry. "
                        "Credentials are not sent on to a redirect."
                    )
                if deadline is None:
                    break
                next_at = max(next_at + args.interval, time.monotonic())
                if next_at >= deadline:
                    break
                time.sleep(max(0.0, next_at - time.monotonic()))
        except KeyboardInterrupt:
            pass
    print(f"{captured} captured, {failed} failed, index at {index_path}")


if __name__ == "__main__":
    main()
