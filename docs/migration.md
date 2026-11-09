# Swift에서 Dart로 옮긴 과정과 검증 근거

## 기준 버전

[원본 v1.0 Add-to-App Release](https://github.com/CodingBot000/FleetBridge/releases/tag/v1.0-add-to-app)의 [커밋 ec218ab](https://github.com/CodingBot000/FleetBridge/commit/ec218ab088e5120c9d874823b893f83f8d2b64e9)를 기준으로 이전했습니다. 원본 저장소는 참조용으로 유지하고 새 앱과 Git 이력, 빌드 산출물을 분리했습니다.

Full Flutter v1.0 검증 대상은 PR #1의 `20a59735849ca11558d5ff0c33c4dc932b95aeb8`입니다. 이후 squash merge한 `bd67b4e33fcb76a1f59cc91b6dc8b99de1d13f1a`에 [v1.0-full-flutter Release](https://github.com/CodingBot000/FleetBridge-Flutter/releases/tag/v1.0-full-flutter)를 게시했습니다. 아래 실행 결과는 2026-11-09 기록이며, 새로 실행하지 않은 검증은 포함하지 않습니다.

## 무엇을 이전했는가

기존 앱에서는 UIKit이 목록을 표시하고 Swift 저장소가 차량 상태를 관리했습니다. 상세를 열 때 FlutterEngine을 생성하고 MethodChannel로 데이터를 전달했습니다. 새 앱에서는 목록과 상세가 같은 Dart 저장소를 사용하며 Flutter Navigator로 이동합니다.

| 원본 구현 | 새 구현 | 이전한 책임 |
| --- | --- | --- |
| Swift `Vehicle` | Dart [`Vehicle`](../lib/vehicle.dart) | 차량 스냅샷과 revision |
| Swift `VehicleRepository` | Dart [`VehicleRepository`](../lib/vehicle.dart) | 초기 데이터, 주기적 갱신, 명령 처리 |
| UIKit `ViewController` | [`VehicleList`, `FleetApp`](../lib/main.dart) | 목록, 검색, 앱 생명주기 대응 |
| `VehicleDetailCoordinator`, FlutterEngine, MethodChannel | [`VehicleDetail`, Navigator](../lib/main.dart) | 상세 진입·복귀와 화면 생명주기 |
| Flutter `VehicleDashboard`, revision gate | `VehicleDetail`, 저장소의 `apply` | 지도와 명령 UI, 중복·역순 갱신 거부 |

원본 구현은 [Swift 모델·저장소](https://github.com/CodingBot000/FleetBridge/blob/ec218ab088e5120c9d874823b893f83f8d2b64e9/FleetBridgeHost/FleetBridgeHost/Vehicle.swift)와 [상세 화면 연결 코드](https://github.com/CodingBot000/FleetBridge/blob/ec218ab088e5120c9d874823b893f83f8d2b64e9/FleetBridgeHost/FleetBridgeHost/VehicleDetailCoordinator.swift)에서 확인할 수 있습니다.

차량 데이터용 MethodChannel과 앱에서 직접 하던 FlutterEngine 관리는 제거했습니다. 출처 링크를 여는 `url_launcher` 등 플러그인의 플랫폼 연동까지 제거한 것은 아닙니다.

## 상태와 자원의 소유권

Riverpod의 일반 `Provider`가 `VehicleRepository` 하나를 생성하고 공유하며 해제합니다. 저장소는 `ChangeNotifier`로 변경을 알리고, 목록과 상세의 `ListenableBuilder`가 이를 구독합니다. `ref.watch(repositoryProvider)`만으로 저장소 내부 변경을 구독하는 구조는 아닙니다.

저장소는 차량 데이터, 차량별 처리 중 명령, 갱신 타이머를 소유합니다. 상세 화면은 선택한 명령 시나리오, 결과 메시지, 지도 오류 상태를 소유합니다. 이렇게 나누면 상세 화면을 닫아도 차량 상태는 유지하고 화면의 임시 상태는 다음 진입에 넘기지 않을 수 있습니다.

화면이 사라지면 위젯의 구독이 해제됩니다. 앱이 백그라운드로 가면 주기적 타이머를 멈추고 복귀 시 다시 시작합니다. 놓친 갱신 횟수를 한꺼번에 처리하지는 않습니다. 저장소를 해제할 때도 타이머를 정리합니다. 이러한 설계와 기기에서 실제 확인한 범위는 구분하며, 아래 표에 검증 방법을 명시했습니다.

## 유지한 동작과 의도적으로 바꾼 동작

| 항목 | 처리 방식 |
| --- | --- |
| 초기 차량 10대 | ID, 이름, 모델, 좌표, 상태, 배터리 초기값을 유지 |
| 주기적 갱신 | 5초 주기, 운행 차량 이동, 오프라인 차량 갱신 중단을 유지 |
| 상태·배터리 변화 | revision이 6의 배수일 때 상태 전환, 12의 배수일 때 배터리 감소를 유지. 명령도 revision을 올리므로 갱신 주기와 연결되는 원본 규칙까지 보존 |
| 명령 결과 | 성공·실패는 1초, 시간 초과 시나리오는 3초 후 결과 반환. 실제 서버 응답에 제한 시간을 적용하는 기능은 아님 |
| revision 필터 | 원본 상세의 채널 이벤트 필터를 Dart 저장소의 스냅샷 적용 단계로 이동 |
| 명령 도중 오프라인 전환 | 원본은 시작 시점만 검사. 새 구현은 완료 시점에도 검사해 성공 처리를 차단하도록 변경 |
| 상세 종료 후 명령 응답 | 이미 시작한 명령은 공유 저장소에서 완료할 수 있고, 닫힌 화면은 응답을 무시하는 동작을 유지 |
| ID 검색·지도 재시도 | 새 앱에 추가한 기능 |

## 발견한 문제와 수정

### 지도 오류가 화면에 계속 남는 문제

타일 로딩 오류 후 오류 플래그가 해제되지 않아 같은 상세 화면에서 오류 메시지가 계속 표시됐습니다. `지도 다시 시도`를 누르면 TileLayer를 새로 만들고 오류 상태를 초기화하도록 수정했습니다. 이전 시도에서 예약된 오류 콜백은 시도 번호를 비교해 새 상태에 반영하지 않습니다.

[지도 재시도 테스트](../test/map_retry_test.dart)는 잘못된 이미지 데이터로 오류를 만든 뒤 정상 PNG로 바꾸고 재시도를 눌러 메시지가 사라지는지 확인합니다. 같은 테스트를 [Android에서도 실행](../integration_test/map_error_test.dart)했습니다. 이는 수동 재시도 검증이며, 네트워크 복구를 자동 감지하는 기능이나 실제 통신 장애 검증은 아닙니다. 이전 콜백의 지연 도착만을 별도로 재현하는 테스트는 없습니다.

### 상세를 닫은 뒤 도착하는 명령 응답

화면이 저장소보다 먼저 종료될 수 있어 응답을 화면에 반영하기 전에 `mounted`를 확인합니다. [위젯 테스트](../test/widget_test.dart)에서는 명령 완료를 `Completer`로 지연시키고 상세를 닫은 뒤 완료해 예외가 발생하지 않는지 확인했습니다. 저장소의 명령 처리와 화면의 결과 표시를 분리하기 위한 조치입니다.

### 플랫폼에 따라 달랐던 테스트 이미지 처리

지도 오류 테스트에 사용한 정상 이미지가 Android 디코더에서 실패해 PNG 데이터를 교체했습니다. 로컬 위젯 테스트만으로는 발견되지 않았고, 에뮬레이터에서 같은 테스트를 실행하며 확인한 문제입니다.

## 동등성을 확인한 방법

Swift와 Dart 구현을 동시에 실행해 결과를 자동 비교한 것은 아닙니다. **원본 코드를 읽어 기대값과 규칙을 정하고, 그 값을 Dart 테스트에서 확인했습니다.** 현재 테스트는 주요 동작에 대한 근거이며 전체 상태 조합의 동등성을 증명하지는 않습니다.

| 원본의 검증 대상 | 새 테스트와 확인 범위 |
| --- | --- |
| `VehicleRepositoryTests` | [widget_test.dart](../test/widget_test.dart): 초기 값, ID 중복 여부, 잘못된 ID 조회 |
| `VehicleSimulationTests` | 같은 파일: 운행 위치 변경, 대기 위치 유지, 오프라인 동결, 상태·배터리 변화 |
| Swift 명령 테스트 | 같은 파일: 성공·실패·시간 초과, 중복 요청 거부, 오프라인 거부 |
| Flutter revision gate | 같은 파일: 동일 revision과 이전 revision 거부 |
| 상세 화면과 명령 UI | [device_test.dart](../integration_test/device_test.dart): 목록·상세 이동, 명령 결과, 버튼 비활성화, 다른 차량 진입 시 상태 격리 |
| 앱 생명주기·지연 응답 | 위젯 테스트의 생명주기 이벤트와 지연 완료: 타이머 실행 여부, 상세 종료 후 예외 여부 |

[원본 Swift 테스트](https://github.com/CodingBot000/FleetBridge/blob/ec218ab088e5120c9d874823b893f83f8d2b64e9/FleetBridgeHost/FleetBridgeHostTests/FleetBridgeHostTests.swift) · [원본 Flutter 테스트](https://github.com/CodingBot000/FleetBridge/blob/ec218ab088e5120c9d874823b893f83f8d2b64e9/fleetbridge_detail/test/widget_test.dart)

## 실행 결과와 한계

| 환경 | 실행한 검증 | 결과·근거 |
| --- | --- | --- |
| 로컬 / GitHub Actions | 분석, 단위·위젯 테스트 | 통과 — [v1.0 CI 실행](https://github.com/CodingBot000/FleetBridge-Flutter/actions/runs/42596492873) |
| Pixel 9 API 36 Emulator | Android 디버그 APK 빌드·실행, 화면 이동, 명령 3종, 처리 중·오프라인 차단, 상태 격리 | 통합 테스트 통과 — [상세](screenshots/android-detail.png), [성공](screenshots/android-command-success.png), [실패](screenshots/android-command-failure.png), [시간 초과](screenshots/android-command-timeout.png) |
| iPhone 17 Pro iOS 26.5 Simulator | Simulator 빌드·실행, 동일한 화면·명령 흐름 | 통합 테스트 통과 — [기존 상세·명령 실행 화면](screenshots/ios-detail.png) |
| Android Emulator | 이미지 오류 주입 후 지도 재시도 | 통과. 실제 네트워크 단절은 아님 |
| Android Emulator | 출처 링크 클릭 | 시스템 로그에서 openstreetmap.org로 향하는 VIEW intent와 Chrome 호출 확인. Chrome 첫 실행 화면으로 목적지 페이지 표시는 미확인 |

기기 통합 테스트는 로컬에서 별도로 실행했습니다. [CI 설정](../.github/workflows/flutter-ci.yml)은 PR에서 분석과 단위·위젯 테스트만 실행합니다. 지도 타일이 실제로 보였다는 근거는 스크린샷이며, 통합 테스트의 지도 assertion은 위젯과 마커 존재를 검사합니다. [출처 링크 테스트](../integration_test/attribution_test.dart)도 클릭 후 대기만 하므로, 테스트 통과 자체가 외부 페이지 표시 성공을 뜻하지는 않습니다.

실물 iOS·Android 기기, 실제 네트워크 단절·복구, 기기 수준의 백그라운드·복귀는 미검증입니다. 차량 및 명령은 모두 시뮬레이션이고 실제 차량·서버와 연결하지 않습니다. 지도는 네트워크와 OpenStreetMap 서비스에 의존하며, flutter_map 캐시는 오프라인 동작을 보장하지 않습니다. 타일 이용 조건은 [OpenStreetMap 정책](https://operations.osmfoundation.org/policies/tiles/)을 따릅니다.

## 검증 재현 방법

README의 환경 준비와 의존성 설치를 마친 뒤 `flutter devices`에서 대상 ID를 확인합니다. 아래 `<android-device-id>`와 `<ios-simulator-id>`를 실제 값으로 바꿉니다.

```sh
flutter analyze
flutter test

# Android: 화면·명령 통합 테스트와 스크린샷 저장
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/device_test.dart -d <android-device-id>

# iOS: 같은 화면·명령 흐름 검증
flutter test integration_test/device_test.dart -d <ios-simulator-id>

# Android: 이미지 오류 주입과 재시도
flutter test integration_test/map_error_test.dart -d <android-device-id>

# Android: 출처 클릭. 외부 브라우저와 목적지 확인은 별도로 필요
flutter test integration_test/attribution_test.dart -d <android-device-id>
```

Android 스크린샷은 [전용 드라이버](../test_driver/integration_test.dart)가 `docs/screenshots/android-*.png`에 저장하며 기존 파일을 덮어씁니다. iOS 분기에서는 이 테스트의 스크린샷 저장을 건너뜁니다. 이미지 갱신 여부는 커밋 전에 확인하세요.
