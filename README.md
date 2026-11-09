# FleetBridge Flutter

**UIKit·Swift와 Flutter가 함께 동작하던 차량 관리 앱을, iOS와 Android에서 실행되는 독립 Flutter 앱으로 이전한 프로젝트입니다.**

화면을 옮기는 데 그치지 않고 Swift가 관리하던 차량 상태, 주기적 갱신, 냉동기 명령 처리를 Dart로 이전했습니다. 원본 코드의 동작을 기준으로 테스트 기대값을 작성하고, 두 플랫폼에서 화면 이동과 명령 흐름을 확인했습니다.

- **데이터와 로직 이전:** 차량 10대의 초기 데이터, 위치·상태·배터리 갱신 규칙, 명령 결과를 Dart에서 처리합니다.
- **화면과 생명주기 통합:** UIKit 목록과 Flutter 상세를 Flutter Navigator로 연결하고, 차량 데이터용 MethodChannel과 수동 FlutterEngine 관리를 제거했습니다.
- **동등성 검증:** 단위·위젯 테스트와 iOS Simulator·Android Emulator 통합 테스트로 유지한 동작과 변경한 동작을 구분했습니다.

차량 데이터와 냉동기 명령은 모두 시뮬레이션입니다. 실제 차량이나 관제 서버에는 연결하지 않습니다.

[Stable Release](https://github.com/CodingBot000/FleetBridge-Flutter/releases/tag/v1.0-full-flutter) · [v1.0 검증 CI](https://github.com/CodingBot000/FleetBridge-Flutter/actions/runs/42596492873) · [이전 과정과 검증 근거](docs/migration.md) · [범위와 완료 기준](docs/specs/full-flutter-migration.md)

## 실행 화면

| iOS — 차량 상세·명령 성공 | Android — 차량 상세·지도 |
| --- | --- |
| <img src="docs/screenshots/ios-detail.png" width="280" alt="iPhone 17 Pro 시뮬레이터의 차량 상세와 냉동기 명령 성공 화면"> | <img src="docs/screenshots/android-detail.png" width="280" alt="Pixel 9 에뮬레이터의 차량 상세와 OpenStreetMap 차량 마커"> |

Android 명령 결과: [성공](docs/screenshots/android-command-success.png) · [실패](docs/screenshots/android-command-failure.png) · [시간 초과](docs/screenshots/android-command-timeout.png)

## 두 단계로 진행한 마이그레이션

| 단계 | 구성 | 확인하려는 문제 |
| --- | --- | --- |
| [1. Native iOS + Flutter Add-to-App](https://github.com/CodingBot000/FleetBridge/releases/tag/v1.0-add-to-app) | UIKit 목록 + Swift 저장소 + Flutter 상세 | 기존 네이티브 앱에 Flutter 화면을 연결하는 방법 |
| [2. Full Flutter Migration](https://github.com/CodingBot000/FleetBridge-Flutter/releases/tag/v1.0-full-flutter) — 현재 저장소 | Flutter 목록·상세 + Dart 저장소 | 데이터와 명령 처리까지 이전하면서 기존 동작을 유지하는 방법 |

[원본 FleetBridge](https://github.com/CodingBot000/FleetBridge)와 이 저장소는 독립된 Git 이력을 유지합니다. 새 앱은 원본의 소스나 빌드 산출물에 런타임 의존하지 않습니다.

## 기능과 구조

차량 ID 검색, 목록과 상세 이동, 운행·대기·오프라인 상태, 위치·배터리·마지막 갱신 시각을 제공합니다. 상세 화면에서는 OpenStreetMap 지도와 차량 마커를 확인하고 냉동기 명령의 성공·실패·시간 초과 시나리오를 실행할 수 있습니다. 처리 중인 차량의 중복 요청과 오프라인 차량의 명령은 차단합니다.

| 구성 | 역할 |
| --- | --- |
| Flutter 3.47.9 / Dart | iOS·Android 공통 UI와 비즈니스 로직 |
| Riverpod `Provider` | 하나의 `VehicleRepository`를 생성·공유·해제 |
| `ChangeNotifier` + `ListenableBuilder` | 저장소의 상태 변경을 화면에 반영 |
| Flutter Navigator | 목록·상세 이동과 화면 생명주기 |
| flutter_map / OpenStreetMap | 지도 타일, 차량 마커, 출처 표시 |

Riverpod이 저장소 내부 변경을 직접 구독하는 구조는 아닙니다. 화면 갱신은 `ListenableBuilder`가 담당합니다. 차량 데이터용 네이티브 채널은 제거했지만, 출처 링크를 여는 Flutter 플러그인의 플랫폼 연동은 사용합니다.

## 검증 결과

아래 결과는 **2026-11-09 v1.0 검증 기록**을 기준으로 합니다.

| 검증 항목 | 환경·방법 | 결과와 근거 |
| --- | --- | --- |
| 정적 분석, 단위·위젯 테스트 | 로컬 및 GitHub Actions | 통과 — [CI 실행](https://github.com/CodingBot000/FleetBridge-Flutter/actions/runs/42596492873), [테스트 코드](test/) |
| 목록·상세 이동, 명령 3종, 처리 중·오프라인 차단, 차량별 상태 격리 | Pixel 9 API 36 Emulator / iPhone 17 Pro iOS 26.5 Simulator | 통합 테스트 통과 — [실행한 테스트](integration_test/device_test.dart) |
| 지도 타일과 마커 표시 | 두 플랫폼의 실행 화면 확인 | [iOS](docs/screenshots/ios-detail.png), [Android](docs/screenshots/android-detail.png) |
| 지도 오류 후 재시도 | Android Emulator에서 잘못된 이미지 데이터를 주입한 뒤 정상 이미지로 교체 | 통과 — [오류 주입 테스트](test/map_retry_test.dart). 실제 통신 장애 검증은 아님 |
| 백그라운드·복귀 시 타이머 제어 | 위젯 테스트에서 생명주기 이벤트 전달 | 통과 — [생명주기 테스트](test/widget_test.dart). 기기 수준 전환은 미검증 |
| Android 출처 링크 | 링크 클릭 후 시스템 로그와 전면 앱 확인 | Chrome 호출 확인. 첫 실행 화면으로 인해 목적지 페이지 표시는 미검증 |

**CI는 분석과 단위·위젯 테스트를 실행합니다. 기기 통합 테스트는 로컬에서 별도로 실행했습니다.** 원본 Swift와 Dart를 동시에 실행해 결과를 자동 대조한 것은 아니며, 원본 코드를 읽고 정한 기대값으로 Dart 동작을 검증했습니다.

실물 기기, 실제 네트워크 단절·복구, 기기 수준의 백그라운드·복귀는 검증하지 않았습니다. 지도 캐시는 오프라인 사용을 보장하지 않습니다. 세부 근거와 의도적인 동작 차이는 [마이그레이션 문서](docs/migration.md)에 정리했습니다.

## 실행 방법

Flutter 3.47.9를 PATH에 등록하고 대상 플랫폼의 개발 도구를 준비합니다. iOS 실행에는 macOS와 Xcode, Android 실행에는 Android SDK와 에뮬레이터 또는 연결된 기기가 필요합니다.

```sh
flutter --version
flutter doctor
flutter pub get --enforce-lockfile
flutter devices
flutter run -d <device-id>
```

`<device-id>`는 `flutter devices`에 표시된 실제 ID로 바꿉니다.

```sh
flutter analyze
flutter test
```

기기 통합 테스트와 Android 스크린샷 생성 명령은 [검증 재현 방법](docs/migration.md#검증-재현-방법)을 참고하세요.
