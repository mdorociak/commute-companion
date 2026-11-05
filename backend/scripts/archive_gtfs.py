import argparse
import base64
import hashlib
import io
import netrc
import os
import sys
import zipfile
import zlib
from datetime import UTC, datetime
from http.client import HTTPException
from pathlib import Path
from urllib.error import HTTPError, URLError
from urllib.parse import urlsplit
from urllib.request import Request, urlopen

DEFAULT_OUT = Path(__file__).resolve().parents[1] / "data" / "kd_gtfs_exports"
MAX_BYTES = 20 * 1024 * 1024
REQUIRED_FILES = (
    "stops.txt",
    "routes.txt",
    "trips.txt",
    "stop_times.txt",
    "calendar.txt",
    "calendar_dates.txt",
    "feed_info.txt",
)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Save one copy of the KD static GTFS export. The link comes from "
            "KD_GTFS_URL, the login and password, if the host has one, from "
            "the ~/.netrc entry for its host."
        ),
    )
    parser.add_argument("--timeout", type=float, default=60.0, help="seconds")
    parser.add_argument("--out", type=Path, default=DEFAULT_OUT)
    return parser.parse_args()


def feed_url() -> str:
    url = os.environ.get("KD_GTFS_URL", "").strip()
    if not url:
        raise SystemExit("KD_GTFS_URL is not set")
    parts = urlsplit(url)
    if parts.scheme not in ("http", "https") or not parts.hostname:
        raise SystemExit(
            "KD_GTFS_URL must look like https://host/path; "
            f"parsed scheme {parts.scheme!r}, host {parts.hostname!r}"
        )
    return url


def basic_auth(url: str) -> str | None:
    parts = urlsplit(url)
    if parts.hostname is None:
        raise SystemExit("KD_GTFS_URL has no host")
    try:
        entry = netrc.netrc().authenticators(parts.hostname)
    except FileNotFoundError:
        return None
    except netrc.NetrcParseError as error:
        raise SystemExit(f"cannot read ~/.netrc: {error}") from error
    if entry is None:
        return None
    if parts.scheme != "https":
        print("warning: KD_GTFS_URL is not https; the password travels in clear",
              file=sys.stderr)
    login, _, password = entry
    token = base64.b64encode(f"{login}:{password}".encode()).decode("ascii")
    return f"Basic {token}"


def download(url: str, auth: str | None, timeout: float) -> bytes:
    request = Request(url)
    if auth is not None:
        request.add_unredirected_header("Authorization", auth)
    try:
        with urlopen(request, timeout=timeout) as response:
            body = response.read(MAX_BYTES + 1)
    except HTTPError as error:
        if error.code in (401, 403):
            raise SystemExit(
                f"HTTP {error.code}: the export refused access; check the "
                "~/.netrc entry. Credentials are not sent on to a redirect."
            ) from error
        raise SystemExit(f"HTTP {error.code} {error.reason}") from error
    except (URLError, OSError, HTTPException) as error:
        raise SystemExit(str(getattr(error, "reason", error))) from error
    if len(body) > MAX_BYTES:
        raise SystemExit(f"body larger than {MAX_BYTES} bytes")
    return body


def problem(body: bytes) -> str | None:
    try:
        with zipfile.ZipFile(io.BytesIO(body)) as archive:
            corrupt = archive.testzip()
            names = set(archive.namelist())
    except (zipfile.BadZipFile, zlib.error) as error:
        return f"body is not a readable zip: {error}"
    if corrupt is not None:
        return f"{corrupt} fails its checksum"
    missing = [name for name in REQUIRED_FILES if name not in names]
    if missing:
        return f"export lacks {', '.join(missing)}"
    return None


def save(body: bytes, name: str, out: Path) -> Path:
    path = out / name
    partial = out / f"{name}.part"
    partial.write_bytes(body)
    partial.replace(path)
    return path


def main() -> None:
    args = parse_args()
    url = feed_url()
    body = download(url, basic_auth(url), args.timeout)
    args.out.mkdir(parents=True, exist_ok=True)
    stem = f"google_transit_{datetime.now(UTC):%Y%m%dT%H%M%SZ}"
    digest = hashlib.sha256(body).hexdigest()
    error = problem(body)
    if error is not None:
        path = save(body, f"{stem}.invalid", args.out)
        raise SystemExit(f"{error}; kept at {path}")
    path = save(body, f"{stem}.zip", args.out)
    print(f"{path} {len(body)} B, sha256 {digest}")


if __name__ == "__main__":
    main()
