# FleetBridge Flutter

## v1.1 개발 — 선택 가능한 Remote 데이터 소스

기본 Local 시뮬레이터에 더해, 로컬 Mock REST API를 선택할 수 있습니다. Remote에서는 서버만 차량 상태를 변경하며 앱은 실제 HTTP로 목록·상세·명령 결과를 가져옵니다. 응답 대기시간이 지나면 실패로 확정하지 않고 ‘결과 확인 필요’로 표시합니다. 요청 ID로 결과를 확인하기 전에는 같은 차량에 새 명령을 보내지 않습니다.

[실행과 승인된 명령 정책](docs/specs/v1.1-remote-data.md) · [v1.1 검증 기록](docs/remote-data.md)

아래 v1.0 기록과 Release는 Full Flutter 이전 당시의 검증 범위를 설명합니다.

A standalone iOS and Android fleet simulation migrated from [FleetBridge v1.0 Add-to-App](https://github.com/CodingBot000/FleetBridge/releases/tag/v1.0-add-to-app). It simulates ten vehicles, live state and location updates, an OpenStreetMap detail view, and refrigeration command outcomes. No real vehicle or server is contacted.

The original architecture connected a UIKit list and Swift repository to an embedded Flutter detail via MethodChannel. Here both screens use a Riverpod-owned Dart repository and Flutter Navigator. See [migration evidence](docs/migration.md) and [contract](docs/specs/full-flutter-migration.md) for mappings, behavior changes and test correspondence.

## Migration series

This is **Part 2** of a two-stage mobile migration case study. The stages are preserved in separate repositories:

- **Part 1 — [Native iOS + Flutter Add-to-App](https://github.com/CodingBot000/FleetBridge/releases/tag/v1.0-add-to-app)** ([source repository](https://github.com/CodingBot000/FleetBridge)): keep the UIKit host and Swift data source while embedding a Flutter detail screen
- **Part 2 — [Full Flutter Migration](https://github.com/CodingBot000/FleetBridge-Flutter/releases/tag/v1.0-full-flutter)** (this repository): migrate the UI and vehicle business logic to shared Dart code for iOS and Android

The repositories have independent Git histories. See [migration evidence](docs/migration.md) for class mappings, behavioral parity, and intentional differences. Both projects use simulated vehicle data and commands.

## Run

Install Flutter 3.47.9 and platform toolchains, then run `flutter pub get` and `flutter run` on an iOS simulator or Android device. `flutter analyze` and `flutter test` run static analysis and automated checks. CI runs these checks on pull requests to main.

Maps use OpenStreetMap tiles over the network, with visible attribution and an error message. The flutter_map HTTP cache is opportunistic, not an offline guarantee. Commands and connectivity states are simulations.

## Verification

`flutter analyze`, `flutter test` and the PR CI validate static analysis and deterministic tests. Pixel 9 API 36 and iPhone 17 Pro iOS 26.5 emulator/simulator integration tests exercised navigation, command outcomes, pending and offline controls, and state isolation. Android map tiles and marker were observed. Tile errors and retry were tested with injected failures on Android. The attribution tap opened Chrome's first-run screen; the destination page was not verified. Physical devices, real network outages and device background/resume remain unverified. See [migration evidence](docs/migration.md) for comparisons and limits.

![iOS vehicle detail](docs/screenshots/ios-detail.png)
![Android vehicle detail](docs/screenshots/android-detail.png)
![Android simulated command success](docs/screenshots/android-command-success.png)
[Android command failure](docs/screenshots/android-command-failure.png) · [Android command timeout](docs/screenshots/android-command-timeout.png)
