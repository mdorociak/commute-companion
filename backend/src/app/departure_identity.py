import json
from dataclasses import dataclass
from datetime import date
from uuid import UUID, uuid5


# This namespace is part of the public ID algorithm and must remain stable.
_DEPARTURE_ID_NAMESPACE = UUID("1a41ca26-bd1c-5a7e-96b8-e7cbb350ce24")


@dataclass(frozen=True)
class ScheduledStopEventIdentity:
    provider_id: str
    service_date: date
    provider_trip_id: str
    provider_stop_id: str
    stop_sequence: int

    @property
    def opaque_id(self) -> str:
        canonical_name = json.dumps(
            [
                self.provider_id,
                self.service_date.isoformat(),
                self.provider_trip_id,
                self.provider_stop_id,
                self.stop_sequence,
            ],
            ensure_ascii=False,
            separators=(",", ":"),
        )
        return f"dep_{uuid5(_DEPARTURE_ID_NAMESPACE, canonical_name).hex}"
