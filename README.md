# Commuter App

[![Backend](https://github.com/mdorociak/commuter-app/actions/workflows/backend.yml/badge.svg)](https://github.com/mdorociak/commuter-app/actions/workflows/backend.yml)

An iOS commuter companion for the Brzeg → Wrocław/Opole train commute. Combines Koleje Dolnośląskie (KD) train schedules and real-time delays with MPK Wrocław city transit connections, so you can see not just when the next train leaves but whether you'll still catch your tram at the other end.


---

## What it does

- **Live departures** from any KD station, adjusted to the current time and service day.
- **Station search & selection** — pick any stop; the choice is remembered across launches.
- **Favorite stops**, persisted locally and surviving relaunches.
- **Works offline** — schedules are cached on device; the app shows the last-known board
  (clearly flagged as cached) when there's no connection.
- *(Planned)* **Connections**: for each train, the tram/bus connections at Wrocław Główny,
  adjusted for real-time delays.

Opole is intentionally **train-only** (no public city-transit API is available there) — a
deliberate graceful-degradation case rather than a missing feature.

---

## Current stage of the project


**What's built today:**

- Backend: full static GTFS pipeline, four endpoints, in-memory model, GitHub Actions CI, tests.
- iOS: four-tab app (Commute / Explore / Saved / Alerts), enum-based navigation, 
  networking to the backend, dynamic station search & selection, SwiftData favorites, 
  tiered cache on both departures and stops, offline-capable, unit-tests.

**Not yet built (planned):**

- Real-time delays and vehicle positions (KD GTFS-RT protobuf feeds).
- Tram/bus connections at Wrocław Główny (MPK Wrocław integration).
- Saved commute *routes* (origin → destination), as opposed to single favorite stops.
- Explore map and Alerts tabs (currently placeholders).

---