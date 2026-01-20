
This document is a guided tour of the `cocobuoys` codebase for a beginner to Swift. It explains how the app works, what the major parts are, and what is specific to Swift and SwiftUI. It also contrasts Swift conventions with JS/React and Python, and closes with distribution considerations for shipping this app to many people.

---

## 1) What this repo contains (big picture)

This repo has two major pieces:

- iOS app (Swift/SwiftUI): `/cocobuoys/cocobuoys/`
- Backend (Node/Express + Mongo): `/surf_app_backend/`

The iOS app fetches buoy data and history from `https://api.surfbuoys.com` and uses push notifications to let users subscribe to station alerts. The backend exposes endpoints the app calls for buoy data and alert subscriptions.

### High-level data flow

1. App launches (`cocobuoysApp.swift`).
2. App asks for location permission (`LocationManager`).
3. App fetches nearby buoys from `api.surfbuoys.com` (`NOAANdbcService`).
4. Buoys are rendered on a map (`SatelliteMapView` + `StationAnnotationView`).
5. Tapping a station opens station history charts (`StationDetailView` + `StationHistoryViewModel`).
6. Users can opt into alerts (push notifications) in `AlertsSignupView`.

---

## 2) App structure and key files

### Entry point

- `cocobuoys/cocobuoys/cocobuoysApp.swift`
  - `@main` app entry point.
  - `AppDelegate` configures push notifications.
  - `PushManager` handles token registration and notification authorization.
  - `AlertsService` wraps alert API endpoints.
  - `AlertsSignupView` and supporting UI for subscribing to alerts live here.

### Root view

- `cocobuoys/cocobuoys/ContentView.swift`
  - The main UI shell.
  - Creates a `MapScreenViewModel`.
  - Shows map, menu buttons, alerts sheet, home summary, and timelapse control.

### Map and map annotations

- `cocobuoys/cocobuoys/Map/SatelliteMapView.swift`
  - Wraps `MKMapView` for SwiftUI.
  - Uses a `Coordinator` to manage region updates and annotations.
- `cocobuoys/cocobuoys/Map/StationAnnotation.swift`
  - Data wrapper for map annotations; each station can render as wave or wind.
- `cocobuoys/cocobuoys/Map/StationAnnotationView.swift`
  - Custom triangle marker for wave stations.
- `cocobuoys/cocobuoys/Map/WindAnnotationView.swift`
  - Custom arrow marker for wind stations.

### View models (state + business logic)

- `cocobuoys/cocobuoys/ViewModels/MapScreenViewModel.swift`
  - Orchestrates map state, fetches buoys, builds annotations, handles timelapse.
- `cocobuoys/cocobuoys/ViewModels/StationHistoryViewModel.swift`
  - Loads station history and drives chart selections.
- `cocobuoys/cocobuoys/ViewModels/AlertsViewModel.swift`
  - Placeholder file (currently empty).

### Views

- `cocobuoys/cocobuoys/Views/StationDetailView.swift`
  - Station history chart with metric selection, pan/zoom, and selection.
- `cocobuoys/cocobuoys/Views/HomeSummaryBanner.swift`
  - Home summary mini charts, with custom mini line chart logic.
- `cocobuoys/cocobuoys/Views/TimelapseControlView.swift`
  - Timelapse slider UI.
- `cocobuoys/cocobuoys/Views/BuoyDetailView.swift`
  - Older/simpler detail view.

### Models and style

- `cocobuoys/cocobuoys/Models/Buoy.swift`
  - `BuoyObservation`, `Buoy`, and marker style structs.
- `cocobuoys/cocobuoys/Models/HomeSummary.swift`
  - `HomeSummary` for the “Home Conditions” banner.
- `cocobuoys/cocobuoys/Models/MarineStation.swift`
  - Base class for map station types.
- `cocobuoys/cocobuoys/Models/StationColorScale.swift`
  - Color scale logic for waves and wind.

### Services

- `cocobuoys/cocobuoys/Services/NOAANdbcService.swift`
  - Fetches nearby buoys and history from `api.surfbuoys.com`.
- `cocobuoys/cocobuoys/Services/LocationManager.swift`
  - Wraps `CLLocationManager` and publishes authorization + location updates.
- `cocobuoys/cocobuoys/Services/HomeLocationStore.swift`
  - Stores/loads home location in `UserDefaults`.

### App configuration

- `cocobuoys/cocobuoys/Info.plist`
  - Location usage message and background notifications.
- `cocobuoys/cocobuoys/cocobuoys.entitlements`
  - APNs entitlement: `aps-environment`.

---

## 3) How the app works (walkthrough)

### 3.1 App launch + push setup

- `cocobuoysApp.swift` sets the root view: `ContentView()`.
- `AppDelegate` calls `PushManager.shared.configure()`.
- When the user opts into alerts, `PushManager.requestAuthorization()` asks for permission.
- Once APNs returns a device token, `PushManager` posts a notification and calls `AlertsService.registerDevice()`.

### 3.2 Map experience

- `ContentView` creates the map with `SatelliteMapView`.
- The view model (`MapScreenViewModel`) controls the region and annotation data.
- `SatelliteMapView.Coordinator`:
  - Applies map styling (hybrid or OSM tile overlay).
  - Synchronizes annotations and updates map region changes.

**Annotation flow**

- `MapScreenViewModel` fetches nearby buoys.
- For each buoy it creates one or two annotations:
  - Wave annotation (triangle marker).
  - Wind annotation (arrow marker).
- `MKMapView` uses `StationAnnotationView` or `WindAnnotationView` based on the annotation type.

### 3.3 Home summary (banner at top)

- The view model builds `HomeSummary` for wave and wind stations nearest to the home location.
- The banner (`HomeSummaryBanner`) displays mini charts and status text.
- You can tap to open the detailed chart (it selects the nearest station).

### 3.4 Station detail view and charts

- Tapping a station opens `StationDetailView`.
- `StationHistoryViewModel` loads history and exposes available metrics.
- Users can:
  - Pick metrics to chart (up to 2).
  - Pan/zoom or tap to select a specific timestamp.

### 3.5 Timelapse mode

- `MapScreenViewModel` preloads histories for visible buoys.
- It computes a time range and lets you “scrub” through history.
- Annotation styles change based on the current timelapse timestamp.

### 3.6 Alerts / push notifications

- `AlertsSignupView` allows users to subscribe to specific station IDs.
- It talks to the backend through `AlertsService`:
  - `POST /devices/register`
  - `POST /devices/subscribe`
  - `DELETE /devices/unsubscribe`
  - `PUT /devices/subscription/:id`
  - `GET /devices/subscriptions/:token`

---

## 4) Backend overview (Node/Express)

The backend lives in `/surf_app_backend/`.

Key entry points:

- `app.js` sets up Express, CORS, and routes.
- `routes/indexRoutes.js` provides `/nearby-buoys/:lat/:lng`.
- `routes/waveDataRoutes.js` provides station history via `/wavedata/stationId/:stationId`.
- `routes/deviceRoutes.js` handles push notification subscriptions.

The iOS app calls:

- `https://api.surfbuoys.com/nearby-buoys/{lat}/{lng}`
- `https://api.surfbuoys.com/wavedata/stationId/{stationId}`
- `https://api.surfbuoys.com/devices/...` for alerts

---

## 5) Swift 101 (as used here)

### 5.1 Types

Swift is strongly typed. You define types with `struct`, `class`, or `enum`.

- `struct`: value type (copied on assignment).
- `class`: reference type (shared instance).
- `enum`: closed set of values, can carry associated data.

In this codebase:

- `BuoyObservation` is a `struct`.
- `Buoy` is a `class` (inherits `MarineStation`).
- `StationMetric` is an `enum`.

### 5.2 Optionals

An optional is a value that can be `nil`.

- `Double?` means “a Double or nil”.
- You unwrap with `if let` or `guard let`.

Example:

    if let height = observation.heightFeet {
        // height is a real Double here
    }

### 5.3 Properties and computed properties

Properties can store values or compute them.

    var latestObservation: BuoyObservation? {
        observations.last
    }

### 5.4 Protocols

Protocols are interfaces. You can create mocks or swap implementations.

Example:

- `NOAANdbcServicing` defines the data-service contract.
- `NOAANdbcService` implements it.

### 5.5 Async/await and Task

Swift concurrency uses `async`/`await`.

- `async` functions must be called with `await`.
- `Task { ... }` starts async work from sync code.

In this codebase:

- `NOAANdbcService.fetchNearbyBuoys(...)` is `async`.
- `MapScreenViewModel.refreshStations` uses `Task` to call it.

### 5.6 Property wrappers in SwiftUI

SwiftUI uses property wrappers to manage state.

- `@State`: local view state.
- `@StateObject`: owns a reference-type model.
- `@Published`: observable property in a view model.
- `@Environment`: reads environment values (like `dismiss`).
- `@Binding`: two-way connection to state.

Example:

- `ContentView` has `@StateObject private var viewModel = MapScreenViewModel()`.
- `SatelliteMapView` uses `@Binding var region`.

---

## 6) SwiftUI basics (how views are built here)

SwiftUI is declarative: the `body` describes the UI for a given state.

Key ideas:

- Views are structs.
- Modifiers (like `.padding()`, `.background()`) return new views.
- State changes trigger view recomputation.

In this app:

- `ContentView` is a composition of a map, top controls, and overlays.
- `StationDetailView` builds charts based on `viewModel.history`.

---

## 7) Conventions in this codebase

General Swift conventions:

- Types: `PascalCase` (e.g., `MapScreenViewModel`).
- Methods/vars: `camelCase` (e.g., `fetchNearbyBuoys`).
- Enums with `CaseIterable`, `Identifiable` to support SwiftUI loops.
- Use `private` for helpers inside a file.

Pattern conventions:

- View Models are `ObservableObject` with `@Published` properties.
- Views own their view models with `@StateObject`.
- Services are lightweight and injected (or defaulted) for testability.

---

## 8) Differences from JS/React and Python

### 8.1 Compared to JS/React

- Swift is compiled and strongly typed; JS is dynamic.
- SwiftUI is declarative like React, but:
  - `@State` roughly maps to `useState`.
  - `@StateObject` roughly maps to a long-lived class instance.
  - `@Binding` is like a two-way prop binding.
- There’s no virtual DOM; SwiftUI diffs view structures internally.
- Async is `async/await` at the language level (not Promises).

### 8.2 Compared to Python

- Swift is type-safe with optionals; Python is dynamically typed.
- Swift uses `struct` and `class` with value/reference semantics.
- Swift has strict access control (`private`, `fileprivate`, etc.).
- Concurrency is explicit; you must use `async` and `await`.

---

## 9) Practical editing guide

### Change data fetching

- `NOAANdbcService` is where API URLs and parsing live.
- If endpoints change, update here.

### Change map visuals

- Wave markers: `StationAnnotationView`.
- Wind markers: `WindAnnotationView`.
- Marker colors: `StationColorScale`.

### Change the Home Summary

- Logic: `MapScreenViewModel.buildHomeSummary()`.
- Rendering: `HomeSummaryBanner`.

### Change alerts / push behavior

- App side: `PushManager` + `AlertsService` + `AlertsSignupView`.
- Backend: `/surf_app_backend/routes/deviceRoutes.js`.

---

## 10) Distribution considerations (shipping to many people)

### 10.1 iOS app signing

- You need an Apple Developer account.
- Configure bundle identifier, team, and signing in Xcode.
- `cocobuoys.entitlements` must include the APNs environment.
- Ensure `Info.plist` has:
  - `NSLocationWhenInUseUsageDescription`
  - `UIBackgroundModes` includes `remote-notification`

### 10.2 Push notifications at scale

- APNs tokens are per-device. They can change; handle updates.
- `PushManager` already re-registers and notifies the backend.
- Ensure backend cleans up invalid tokens (APNs feedback).
- Use the correct APNs environment (sandbox vs production).

### 10.3 Backend scaling

- Your app depends on:
  - `/nearby-buoys`
  - `/wavedata/stationId`
  - `/devices/...`
- Add caching for buoy data and station history.
- Consider rate limiting, retries, and uptime monitoring.
- Ensure HTTPS and CORS are configured for production origins.

### 10.4 Third‑party services

- Map data:
  - OSM tile usage should respect tile usage policies.
  - Consider a paid tile provider if traffic grows.

### 10.5 App Store requirements

- Privacy: you use location and push notifications.
- Provide a clear privacy policy and explain data usage.
- Keep `Info.plist` permission strings accurate.

### 10.6 QA and testing

- Use TestFlight for beta distribution.
- Add basic unit tests around data mapping and view models.
- Verify notifications with production certificates before release.

---

## 11) Quick reference: where to look first

- App entry + alerts: `cocobuoys/cocobuoys/cocobuoysApp.swift`
- Main UI: `cocobuoys/cocobuoys/ContentView.swift`
- Map state & logic: `cocobuoys/cocobuoys/ViewModels/MapScreenViewModel.swift`
- Networking: `cocobuoys/cocobuoys/Services/NOAANdbcService.swift`
- Station charts: `cocobuoys/cocobuoys/Views/StationDetailView.swift`
- Backend routes: `surf_app_backend/routes/`

---