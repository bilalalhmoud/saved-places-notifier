# Nearby Saved — Google Maps Saved Places Proximity Notifier

An iPhone app that notifies you whenever you're close to **any place you've saved in Google Maps** — even with **thousands** of saved places. It sidesteps iOS's ~100 geofence limit by using a **geohash spatial index** and battery-efficient location monitoring instead of one geofence per place.

> Private by design: everything is stored **on-device**. Your location never leaves your iPhone and no account is required.

---

## Why not geofences?

iOS only allows ~20 region monitors (geofences) per app — nowhere near enough for hundreds or thousands of saved places. Instead of registering a geofence per place, this app:

1. Builds a **geohash spatial index** of all saved places.
2. Watches for **Significant Location Changes** and **Visits** (very low power).
3. On each update, queries the index for the handful of places in the surrounding geohash cells.
4. Runs a precise **Haversine** distance check only on those candidates.
5. Applies user filters (category, transport mode, time window, cooldown) and fires a de-duplicated local notification.

```
Location update → Spatial index query (~9–25 cells) → Haversine on candidates
   → Filter (category / mode / time / cooldown) → Notify → Record to prevent duplicates
```

This scales to **tens of thousands** of places with a nearby search well under 100 ms.

---

## Architecture

The logic that must be correct and fast lives in a **pure Swift package** (`SavedPlacesCore`) with **no UIKit/CoreLocation/SwiftData dependencies**, so it is fully unit-testable in CI without a simulator.

```
saved-places-notifier/
├── Core/                                  # SavedPlacesCore Swift package (pure logic)
│   ├── Sources/SavedPlacesCore/
│   │   ├── Coordinate.swift               # platform-neutral coordinate
│   │   ├── Haversine.swift                # great-circle distance
│   │   ├── Geohash.swift                  # encode + neighbour/grid helpers
│   │   ├── SpatialIndex.swift             # geohash-bucketed proximity search
│   │   ├── PlaceRecord.swift              # value model
│   │   ├── Enums.swift                    # TransportMode, Cooldown (+ adaptive radius)
│   │   ├── TakeoutImporter.swift          # Google Takeout GeoJSON/CSV import
│   │   └── ProximityEngine.swift          # dedup + cooldown + batching + rate limit
│   └── Tests/SavedPlacesCoreTests/        # XCTest suites (run with `swift test`)
├── App/
│   ├── Sources/                           # SwiftUI app, SwiftData, Core Location glue
│   │   ├── SavedPlacesApp.swift           # @main + notification delegate
│   │   ├── AppModel.swift                 # coordinator: location → engine → notifications
│   │   ├── Models/SavedPlace.swift        # @Model persistent record
│   │   ├── Settings/AppSettings.swift     # persisted user settings
│   │   ├── Location/LocationManager.swift # significant-change + visits + adaptive accuracy
│   │   ├── Notifications/NotificationManager.swift
│   │   ├── Import/ImportService.swift
│   │   └── Views/                         # Home, Map, Lists, Search, Settings, Detail
│   ├── Resources/Assets.xcassets
│   └── Tests/                             # app-level XCTest
├── project.yml                            # XcodeGen project definition
├── Samples/                               # example Takeout GeoJSON
└── .github/workflows/ci.yml               # macOS runner: builds + tests everything
```

### Data model (`SavedPlace`)

`id`, `googlePlaceID`, `title`, `latitude`, `longitude`, `address`, `category` (list), `notes`, `tags`, `dateSaved`, `lastNotification`, `lastVisited`, `favourite`, `icon`.

---

## Features

- **Import** Google Maps saved places from a **Google Takeout** export (`.json` / `.geojson` preferred, `.csv` supported best-effort).
- **On-device SQLite** via **SwiftData**.
- **Battery-efficient monitoring**: Significant Location Changes + Visit Monitoring, raising accuracy only when a place is near.
- **Geohash spatial index** — never compares against every place.
- **Adaptive radius** by transport mode (walking ≈ 250–300 m, cycling ≈ 400–500 m, driving ≈ 800–1000 m), auto-detected from speed or set manually.
- **Rich notifications** with actions: Navigate, Open in Google Maps, Mark as visited, Snooze.
- **Duplicate prevention** with a persisted proximity state (notify on entry only; re-notify requires leaving and returning, plus a configurable cooldown).
- **Batching + rate limiting**: "You have N saved places nearby" instead of a flood.
- **Category enable/disable**, **transport-mode** and **time-window** filters (weekdays, weekends, daytime, business hours).
- **UI**: Home (nearby), Map (clustered, colour-coded pins), Lists (categories + smart lists), Search (name/area/tag/notes/category), Settings.

---

## Building

### In CI (recommended — no Mac required to trigger)

Every push to `main` runs [`.github/workflows/ci.yml`](.github/workflows/ci.yml) on a **macOS runner**, which:

1. Runs `swift test` on `SavedPlacesCore` (fast, no simulator).
2. Generates the Xcode project with **XcodeGen**.
3. Builds the iOS app for the simulator (unsigned) and runs the app unit tests.
4. Uploads the built `.app` as a workflow artifact.

### Locally (macOS + Xcode 15+)

```bash
brew install xcodegen
xcodegen generate           # creates SavedPlacesNotifier.xcodeproj
open SavedPlacesNotifier.xcodeproj
# Select the SavedPlacesNotifier scheme and run on a device/simulator.

# Core logic tests only:
cd Core && swift test
```

The Xcode project and generated `Info.plist` are intentionally **git-ignored** — they are produced from `project.yml`.

---

## Importing your places (Google Takeout)

1. Go to **[Google Takeout](https://takeout.google.com/)** → deselect all → select **Saved** (and/or **Maps (your places)**).
2. Export and download the archive, then **unzip** it.
3. In the app, open **Home ▸ Import** (or **Settings ▸ Data**) and pick the `.geojson` / `.json` / `.csv` files. Each file's name becomes the list/category.

The importer extracts name, coordinates, address, notes, Google Maps ID, list/category and date saved. Duplicates are skipped by Google place ID (or coordinates + title).

---

## Privacy

- 100% local storage (SwiftData on device).
- Location is processed on-device and **never uploaded**.
- Works offline; no account, no tracking.

---

## Roadmap

Route-aware alerts (notify about places just off your navigation route), Siri/App Intents, Apple Watch and CarPlay surfaces, travel mode, weather/time-aware suggestions, calendar pre-fetch, AI ranking of nearby options, and shared collections.

---

## License

MIT — see [LICENSE](LICENSE).
