# Full Flutter migration contract

Baseline: FleetBridge v1.0 Add-to-App at ec218ab088e5120c9d874823b893f83f8d2b64e9. Migrate the ten-vehicle list, detail, simulation, OSM map and refrigeration command scenarios. Search by ID is an addition.

`Vehicle` and `VehicleRepository` move from Swift to typed Dart classes. Flutter owns list, navigation and detail. A single Riverpod-owned repository supplies both screens, tracks revisions and owns the timer and command concurrency. Background stops the timer; resume restarts it; disposal cancels it. Delayed command completion must not access a disposed screen or repository.

Parity requires matching initial IDs, status, coordinates, battery, periodic changes and command outcomes, plus rejection of duplicate or older revisions. Test these with controlled clocks/delays and widget navigation. Analyze and test on Flutter 3.47.9; separately report iOS simulator build/run and Android build/run. Maps depend on network and OSM tile policy; simulate failures in tests. Actual vehicles and servers are out of scope.
