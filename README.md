# Commuter Companion

[![Backend CI](https://github.com/mdorociak/commute-companion/actions/workflows/backend.yml/badge.svg)](https://github.com/mdorociak/commute-companion/actions/workflows/backend.yml)
[![iOS CI](https://github.com/mdorociak/commute-companion/actions/workflows/ios.yml/badge.svg)](https://github.com/mdorociak/commute-companion/actions/workflows/ios.yml)

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
- **Departures:** a dedicated feature target with DTO/domain separation, real
  API integration, cancellation-aware state loading, a tested ViewModel, and a
  public scheduled-departures screen with loading, empty, and typed failure
  states.
- **Navigation:** typed station selection composed by `Root` into the scheduled
  departures feature without coupling the feature targets to one another.
- **Continuous integration:** GitHub Actions runs the deterministic backend
  tests, builds the iOS app with Xcode 26.6, and runs the aggregate
  `CommuteCompanionKit` test scheme on an iOS Simulator.

The iOS app now supports an API-backed journey from station discovery and local
search into a selected station's scheduled departure board.

---

## Planned

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
