# Migration evidence

Baseline: [v1.0 Add-to-App release](https://github.com/CodingBot000/FleetBridge/releases/tag/v1.0-add-to-app), [commit ec218ab088e5120c9d874823b893f83f8d2b64e9](https://github.com/CodingBot000/FleetBridge/commit/ec218ab088e5120c9d874823b893f83f8d2b64e9). The original repository is a read-only reference, not a runtime dependency.

| Before | After | Responsibility |
| --- | --- | --- |
| Swift `Vehicle` | Dart `Vehicle` | Typed snapshot and revision |
| Swift `VehicleRepository` | Dart `VehicleRepository` | Simulation and commands |
| UIKit `ViewController` | Flutter `VehicleList`, `FleetApp` | List and lifecycle |
| `VehicleDetailCoordinator`, FlutterEngine, MethodChannel | Flutter Navigator and `VehicleDetail` | Detail and navigation |
| Flutter `VehicleDashboard`, revision gate | `VehicleDetail`, repository `apply` | Map, command UI and revision ordering |

Before: UIKit → Swift repository → MethodChannel → Flutter detail. After: Flutter list/detail → Riverpod-owned Dart repository. Platform channels for vehicle data, manual engine management and UIKit navigation are gone. Flutter plugins still use platform integration for opening the attribution link.

The ten initial records, status cycle, 5-second interval, movement, battery cadence and command delays/scenarios are retained. ID search is new. Commands now also fail if a vehicle becomes offline while pending. A command already dispatched continues after the detail closes, updating the shared repository; the closed screen ignores the result. Revision validation now guards the shared repository. Background pauses the timer and resume restarts it without catch-up.

| Original tests | New coverage |
| --- | --- |
| VehicleRepositoryTests | Initial count, uniqueness, lookup |
| VehicleSimulationTests | Movement, offline, status and battery |
| Swift command tests | Success, failure, timeout, duplicate and offline |
| Flutter revision gate and lifecycle tests | Repository revision gate; lifecycle widget test |
| Flutter detail and command widget tests | Navigation and delayed response after closing; repository command outcomes |

The first widget test exposed that a lazy detail list may not build offscreen controls; a larger test viewport permits deterministic interaction. Lifecycle tests must send the intermediate hidden/inactive states expected by Flutter. A tile failure previously left the error permanently visible on the detail screen. The retry action replaces the tile layer and clears the message; errors from a previous attempt cannot mark the new attempt failed. A retry can fail again and show the message again. The built-in flutter_map tile cache follows HTTP cache headers and platform cache limits; it is opportunistic, not guaranteed offline storage. OSM attribution remains visible. Consult the [OSM tile usage policy](https://operations.osmfoundation.org/policies/tiles/) before deploying at scale.

## Cross-platform verification (2026-11-09)

The exact initial values, driving movement, idle position, offline freeze, status at revision 6, battery at revision 12, duplicate/out-of-order revisions and command outcomes are checked in Dart tests against the Swift baseline. The original uses revision for both commands and simulation cadence; the Dart implementation preserves this coupling. The original detail gate filtered channel events; the Dart repository filters incoming snapshots centrally. Swift's per-detail engine teardown became Flutter route disposal; the repository continues a pending simulated command after route closure, and the disposed screen ignores the result. The original command implementation checks offline only when starting; the Dart version additionally rejects success if the vehicle is offline when it completes. This is an intentional safety difference. Both stop periodic updates in the background and restart without catch-up. Search by ID and explicit map retry are additions.

Riverpod's ordinary `Provider` creates, shares and disposes one `VehicleRepository`. It does not observe ChangeNotifier changes itself: `ListenableBuilder` subscribes to the repository for list and detail rebuilds. The repository owns snapshots, pending command IDs, timer and notifications; the detail owns transient scenario, result and tile-error state. Flutter Navigator owns routes. No architecture replacement was necessary.

- **Android Pixel 9, API 36 emulator:** Flutter integration test drove list → detail → list, verified a marker and captured an actual loaded OSM map, success/failure/timeout outcomes, pending button disabled, offline command disabled and other-vehicle state isolation. Repository test separately verifies duplicate request rejection. An injected failing tile provider followed by a valid image tested error display and retry on the emulator; this is not an actual network outage. Tapping attribution issued an Android VIEW intent to openstreetmap.org and opened Chrome's first-run screen; the site itself was not displayed because Chrome setup was incomplete.
- **iPhone 17 Pro, iOS 26.5 Simulator:** the same navigation, marker, success/failure/timeout, pending/offline controls and vehicle isolation integration flow passed. Prior screenshot shows loaded OSM map and success. Background/resume is covered by a widget lifecycle test, not a device background transition.
- **Limits:** physical devices, real network disconnection and recovery, browser page display on Android, and device-level background/resume were not verified. Tile failure was injected rather than a network outage. The test-driven interactions run on emulators/simulator; they are not manual physical-device testing.
