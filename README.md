# cocobuoys

An iOS SwiftUI app that shows nearby buoy conditions, station history charts,
and optional alert subscriptions (push notifications).

## Features

- Map-based view of wave and wind stations
- Station detail charts with selectable metrics
- Home summary banner with mini trend charts
- Timelapse mode for historical playback
- Push-notification alerts for stations

## Requirements

- macOS with Xcode 15+ (Swift 5.9+)
- iOS 16+ device or simulator
- Backend API (see below)

## Project structure

```
cocobuoys/
  cocobuoys/                iOS app (SwiftUI)
  surf_app_backend/         Node/Express API server
  COCOBUOYS_MANUAL.md       Long-form manual for this repo
```

## Getting started (iOS app)

1. Open `cocobuoys/cocobuoys.xcodeproj` in Xcode.
2. Select a simulator or device.
3. Build and run.

The app calls `https://api.surfbuoys.com` by default. To change the API base URL,
edit `NOAANdbcService` and `AlertsService`.

## Backend (optional for local dev)

The backend lives in `surf_app_backend/`. It provides:

- `/nearby-buoys/:lat/:lng`
- `/wavedata/stationId/:stationId`
- `/devices/...` alert subscription endpoints

Start it with:

```
cd surf_app_backend
npm install
npm start
```

Then update the app base URL to point at your local server.

## Push notifications

Push notifications require:

- Apple Developer account and APNs configuration
- Correct `aps-environment` in `cocobuoys.entitlements`
- Device token registration via `/devices/register`

Note: simulators do not receive real APNs pushes.

## Configuration

- Location permission string: `cocobuoys/Info.plist`
- Background modes: `UIBackgroundModes` in `Info.plist`
- App icon and assets: `cocobuoys/Assets.xcassets`

## Tests

```
Open Xcode -> Product -> Test
```

Tests live in:

- `cocobuoysTests/`
- `cocobuoysUITests/`

## Troubleshooting

- If the map shows no stations, confirm API connectivity.
- If location is denied, enable it in iOS Settings.
- For push alerts, verify APNs environment and device token registration.

---

For a deeper walkthrough, see `COCOBUOYS_MANUAL.md`.
