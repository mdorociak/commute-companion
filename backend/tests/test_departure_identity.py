from dataclasses import replace
from datetime import date

import pytest

from app.departure_identity import ScheduledStopEventIdentity


IDENTITY = ScheduledStopEventIdentity(
    provider_id="kd",
    service_date=date(2026, 5, 20),
    provider_trip_id="38645733_409036",
    provider_stop_id="2333170",
    stop_sequence=4,
)


def test_scheduled_stop_event_id_is_deterministic_and_opaque() -> None:
    recreated = replace(IDENTITY)

    assert IDENTITY.opaque_id == recreated.opaque_id
    assert IDENTITY.opaque_id == "dep_f8a9c26b8a9d5f00bb6386d420915e62"
    assert IDENTITY.opaque_id.startswith("dep_")
    assert IDENTITY.provider_trip_id not in IDENTITY.opaque_id


@pytest.mark.parametrize(
    ("field", "value"),
    [
        ("provider_id", "mpk-wroclaw"),
        ("service_date", date(2026, 5, 21)),
        ("provider_trip_id", "another-trip"),
        ("provider_stop_id", "another-stop"),
        ("stop_sequence", 5),
    ],
)
def test_scheduled_stop_event_id_changes_with_identity_component(
    field: str,
    value: object,
) -> None:
    changed = replace(IDENTITY, **{field: value})

    assert changed.opaque_id != IDENTITY.opaque_id
