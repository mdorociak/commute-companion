# Commuter Companion

[![Backend](https://github.com/mdorociak/commuter-app/actions/workflows/backend.yml/badge.svg)](https://github.com/mdorociak/commuter-app/actions/workflows/backend.yml)

An iOS commuter companion for recurring Brzeg → Wrocław and Brzeg → Opole
journeys. The current implementation combines a FastAPI scheduled-transport
backend with the beginning of a native SwiftUI client. Realtime disruption and
Wrocław city-transit connections remain part of the product direction, not
completed functionality.

---

## What's built today

- **Backend:** static KD GTFS loading, service-calendar and after-midnight
  timetable handling, versioned station and scheduled-departure endpoints,
  stable opaque departure identifiers, and deterministic tests.
- **iOS foundation:** an Xcode application target, one modular local Swift
  package, explicit dependency injection, and a tested provider-neutral HTTP
  client.
- **Stations:** an API-backed SwiftUI station list with local search and
  explicit loading, empty, and failure states.
- **Departures data:** a dedicated feature target with DTO/domain separation,
  ISO-8601 timestamp decoding, a focused repository boundary, real API
  integration, cancellation handling, and deterministic tests.

The next product slice is station selection and a SwiftUI departure board backed
by the existing departures repository.

---

## Planned

- Departure presentation and station-to-departures navigation in the iOS app.
- Realtime delays and vehicle positions integrated into departure responses.
- Tram/bus connections at Wrocław Główny (MPK Wrocław integration).
- Favorites, saved station or commute restoration, and local preferences.
- Offline caching with explicit cached and stale presentation states.
- Saved commute *routes* (origin → destination), as opposed to single favorite
  stops.
- Commute, Explore, Saved, and Alerts product features.

Opole is intentionally train-only in the initial product scope. Realtime,
freshness metadata, caching, and connection calculation must not be presented as
complete until they are integrated and tested end to end.

---
