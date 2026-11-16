# v1.1 원격 데이터 검증 기록

최신 상태는 [Android 복구 및 최종 검증](#android-복구-및-최종-검증)을 참고하세요. 아래 초기 구현·안정화 기록은 해당 시점의 결과를 보존합니다.

v1.0과 달리 실제 HTTP 대기 제한과 서버 측 명령 완료가 서로 독립적입니다. 요청 ID로 결과를 확인하기 전에는 타임아웃을 명령 실패로 확정할 수 없다는 점을 검증합니다. 실행·장애 재현·승인 정책은 [v1.1 명세](specs/v1.1-remote-data.md)를 참고하세요.

## 2026-11-16 검증

- 기존 로컬 테스트를 유지했고 새 HTTP·저장소 테스트를 포함해 Flutter 테스트 12개가 통과했습니다.
- Python 실제 HTTP 테스트 5개에서 목록·상세, 요청 ID 재사용·충돌, 차량별 중복 요청, 연결 종료 뒤 명령 완료, 오프라인 차단, 지연 및 HTTP 503을 확인했습니다.
- 정적 분석이 통과했습니다.
- Pixel 9 API 36 Emulator: Android debug 빌드·설치 후 Remote 통합 테스트 통과. 실제 서버 목록·상세 조회, 성공·실패·지연 명령, 결과 확인 전 새 명령 차단, 결과 조회 후 성공 및 목록 복귀를 확인했습니다.
- iPhone 17 Pro iOS 26.5 Simulator: Simulator 빌드·실행 후 같은 Remote 통합 테스트가 통과했습니다.
- Remote 폴링 중지·늦은 조회 응답 무시·재시작은 위젯 테스트로 확인했습니다. 기기 수준 백그라운드 전환은 이번에 실행하지 않았습니다.
- CI는 PR의 Checks에서 확인할 수 있습니다. Flutter 분석·테스트와 Python HTTP 테스트를 실행하며 기기 통합 테스트는 로컬에서 실행했습니다.

[Android 명령 성공](screenshots/v1.1-remote-success.png) · [Android 결과 확인 필요](screenshots/v1.1-remote-unknown.png)

기기 테스트 중 지도와 상세 목록의 스크롤 제스처가 겹쳐 하단 결과 영역을 찾지 못했습니다. 버튼 영역에서 목록 스크롤을 시작하도록 테스트 입력을 수정했습니다. 앱의 명령 처리 규칙을 바꿔 테스트를 통과시키지는 않았습니다.

실물 기기·외부 서버·실제 차량은 검증하지 않았습니다. 네트워크 연결 종료 테스트는 로컬 서버 프로세스를 종료하거나 로컬 HTTP 대기시간을 제한한 것입니다. 모바일 네트워크 전환·패킷 손실·재부팅 복구는 검증하지 않았습니다.


## 통합 안정화 검증 (PR #4 후속 작업)

### 발견한 결함과 수정

| 결함 | 수정 | 회귀 근거 |
| --- | --- | --- |
| stop/start 후 이전 refresh Future를 재사용하고 이전 finally가 로딩을 해제 | 목록·차량별 요청 객체로 상태 소유권을 식별하고 stop에서 무효화 | [remote_race_test.dart](../test/remote_race_test.dart) |
| 목록·상세 성공이 다른 조회의 오류를 지움 | 목록 오류와 차량별 상세 오류를 분리하고 해당 조회만 갱신 | 같은 경합 테스트와 [UI 테스트](../test/remote_ui_test.dart) |
| 명령 성공 후 이전부터 진행 중인 목록 요청에 합류 | 성공 후 새 목록 요청으로 상태 확인 | 경합 테스트의 pre-command snapshot 사례 |
| 요청 ID만 일치하면 다른 payload의 명령 결과를 인정 | ID·차량·enabled·scenario 전체 비교. 잘못된 응답은 불명확 유지 | [remote_command_test.dart](../test/remote_command_test.dart) |
| POST 상태 코드만으로 접수 거부를 확정 | 상태 코드와 명세의 거부 error 코드를 함께 확인 | 같은 명령 테스트의 400/404/409/422/503·JSON 사례 |
| 서버가 공용 잠금을 잡은 채 응답을 쓰고 헤더 전송 실패를 처리하지 않음 | 잠금 안에서 스냅샷만 복사하고 밖에서 쓰며 연결 종료 처리 | [test_concurrency.py](../mock_server/test_concurrency.py) |

### 검증 범위

- 결정적 Future·Completer 테스트: stop/start 중 요청 교체, 늦은 성공·실패·finally, 중복 refresh, 재진입 알림, 목록·상세 동시 조회, 낮은 revision 거부, dispose 후 응답, 폴링 중단·재개.
- 명령 테스트: 동일 차량 차단, 차량 간 격리, 반복 조회 중복 차단, pending/success/failure, POST 접수 거부와 결과 불명확 구분, 조회 오류·잘못된 JSON·ID와 payload 불일치, dispose 후 응답.
- Python 실제 HTTP: 같은 requestId의 동시 요청, 같은 차량 요청 경합, 다른 차량 동시 실행, revision 1회 증가와 pending 해제, 응답 전 연결 종료, 지연·503, 서버 재시작 뒤 404.
- Dart 실제 HTTP: 서버 프로세스 종료와 503 뒤 복구된 서버 재조회, 최신 차량 상태 반영, 서버가 잃은 명령 기록을 404로 조회해도 차단 유지.
- UI 위젯: 로딩, 이전 정상 데이터 유지, 오류·복구, 상세 종료·재진입의 미확인 명령 표시, 다른 차량·오프라인 차단, 최신 배터리 반영. 실제 네트워크와 UI 가짜 Client 검증을 구분합니다.

플랫폼 실행과 최종 CI 결과는 아래에 확인된 결과만 기록합니다.

### 자체 코드 리뷰

데이터·명령의 상태 소유권, Client·Timer 정리, dispose 이후 응답, 요청 ID와 payload 연결, 중복 조회·알림 재진입, 서버 잠금 범위를 별도 단계에서 검토했습니다. 타이머는 초기 알림 전에 등록하고, 알림 중 stop으로 무효화된 조회는 HTTP를 시작하지 않도록 보완했습니다. ChangeNotifier의 알림 콜백 안에서 직접 dispose하는 사용은 Flutter 계약에 어긋나므로 지원 대상으로 삼지 않습니다. 정상적인 화면 종료·Provider 해제와 진행 중 응답의 경계는 회귀 테스트로 확인합니다.

승인된 메모리 정책에 따른 앱·서버 재시작 시 기록 유실, 서버 revision 초기화 및 인증·영속성·운영 부하 제한의 부재는 계속 남습니다. 소켓 강제 취소나 OS 메모리 프로파일링을 수행한 것으로 표현하지 않습니다. 불명확한 명령을 자동 재전송하거나 영속 저장소를 도입하지 않았습니다.


### 최종 실행 결과 (2026-11-16 통합 안정화)

| 검증 | 결과 |
| --- | --- |
| Flutter 분석 | 통과 |
| Flutter 단위·위젯·실제 HTTP 테스트 | 41개 통과. 실제 HTTP 테스트는 Python 프로세스와 루프백 소켓 사용 |
| Python HTTP·동시성 테스트 | 10개 통과. 동시 명령의 지연은 Event로 제어 |
| iPhone 17 Pro / iOS 26.5 Simulator — Local | 빌드·실행 후 기존 화면 이동·명령·상태 격리 통합 테스트 통과 |
| 같은 iOS Simulator — Remote | 포트 8081의 별도 로컬 서버 사용. 성공·실패·결과 불명확, 화면 재진입·차량 격리·오프라인 차단, 결과 조회 후 성공 통합 테스트 통과 |
| Pixel 9 / API 36 — Remote | debug APK 빌드·설치와 일부 화면·명령 확인. **최신 전체 통합 테스트 미완료**: `10.0.2.2` network unreachable, ADB 연결 중단과 debug log reader 종료 발생. ADB reverse + 127.0.0.1 재시도에서도 디버그 연결 불안정 |
| Pixel 9 — Local | 실행 재시도 시 emulator-5554가 offline / API null로 표시되어 사용 가능한 장치로 인식되지 않음. **이번 안정화 커밋의 Local 실행 미검증** |

Android의 이전 v1.1 검증 결과와 스크린샷은 앞 절의 초기 구현 기록이며, 이번 안정화 커밋의 전체 통과 근거로 사용하지 않습니다. 실패 중 만들어진 이미지로 기존 스크린샷을 교체하지 않았습니다. 다른 작업의 에뮬레이터나 기기 데이터를 변경하지 않았습니다. 안정된 Pixel 9 환경에서 아래 두 명령으로 재검증해야 합니다.

```sh
# 기본 호스트 네트워크가 불안정할 경우의 로컬 개발 연결
adb -s <pixel9-id> reverse tcp:8080 tcp:8080
flutter drive --driver=test_driver/integration_test.dart \
  --target=integration_test/remote_device_test.dart -d <pixel9-id> \
  --dart-define=FLEET_MODE=remote \
  --dart-define=FLEET_API_URL=http://127.0.0.1:8080

FLEET_SCREENSHOT_DIR=/tmp/fleetbridge-local-regression flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/device_test.dart -d <pixel9-id> \
  --dart-define=FLEET_MODE=local
```

드라이버의 `FLEET_SCREENSHOT_DIR`는 회귀 테스트가 기존 실행 증거 이미지를 덮어쓰지 않도록 출력 폴더를 선택하는 설정입니다. iOS 테스트는 스크린샷 저장을 건너뜁니다. CI는 PR 최신 커밋의 Checks에서 확인하며 로컬 기기 검증을 대신하지 않습니다.


## Android 복구 및 최종 검증

### 환경 진단과 복구

기준은 PR #4의 `cb8ea1fecd91c8185f61b304667d6acf05d185ef`입니다. Flutter 3.47.9, Android SDK API 36, ADB 37.0.1, Emulator 37.1.11.0을 확인했습니다. SDK·라이선스·Xcode 진단은 통과했고 SDK를 재설치하지 않았습니다. Flutter의 PATH 경고는 SDK 절대 경로로 실행해 처리했습니다.

기존 Pixel 9는 shell 속성 조회가 지연되고 다른 ADB 서버에서도 offline으로 표시됐습니다. 공용 ADB에는 다른 작업의 AVD가 연결되어 있어 공용 서버를 재시작하지 않았습니다. Pixel 9 프로세스만 정상 종료한 뒤 사용자 데이터를 지우지 않고 cold boot했고 Wi-Fi와 실제 `GET /vehicles` HTTP 200을 확인했습니다. 다만 Flutter 디버그 연결은 안정되지 않았습니다.

허용된 대안으로 `FleetBridge_Readiness_API36_20261116` AVD를 만들었습니다. API 36 / arm64, 720×1280 / 280dpi, RAM 2GB, 2코어, headless, Vulkan 비활성화 구성입니다. 기존 AVD를 초기화하거나 삭제하지 않았습니다. 진단 시 호스트 스왑이 약 58GB 사용 중이었고 에뮬레이터 프레임 지연도 관찰됐습니다. 이는 자원 압박의 증거이지만 모든 실패를 한 원인으로 단정하지는 않습니다.

별도 ADB 서버 5047과 일반 자동 탐색 범위 밖의 console/ADB 포트 5660/5661을 사용해 전용 AVD에 명시적으로 연결했습니다. 자동 탐색 범위에서 디버그 포워딩이 사라지던 현상은 이 구성에서 재현되지 않았습니다. Mock API 연결은 에뮬레이터 안에서 실제 HTTP 응답을 확인한 `10.0.2.2`를 사용했습니다. `adb reverse`도 시험했으나 해당 경로를 최종 성공 근거로 쓰지 않았습니다.

### 발견한 앱 결함과 회귀 검증

차량 데이터가 갱신될 때마다 TileLayer 생성자가 새 타일 HTTP 클라이언트를 만드는 문제가 있었습니다. 갱신 전후 생성 횟수가 1이어야 하는 테스트에서 실제 2로 실패한 뒤 수정했습니다. `VehicleMap`이 지도 요소의 생명주기 동안 provider 하나를 유지하도록 분리했습니다. 지도 재시도는 새 지도 요소를 만들고 기존 클라이언트는 TileLayer가 해제합니다. 앱을 명확히 식별하는 User-Agent도 설정했습니다. [OSM 타일 정책](https://operations.osmfoundation.org/policies/tiles/)의 식별·캐시 조건을 따르며 출처 표시와 기존 캐시를 유지합니다.

[map_lifecycle_test.dart](../test/map_lifecycle_test.dart)의 두 테스트가 클라이언트 재사용, 재시도 시 교체·해제, 화면 종료 시 해제를 검증합니다. 기존 지도 오류 테스트도 그대로 유지했습니다. 명령 처리나 승인된 메모리 정책은 바꾸지 않았습니다.

### 실행 결과

| 검증 | 결과 |
| --- | --- |
| Flutter 분석 | 통과. 최신 PR 커밋의 CI도 별도로 확인 |
| 기존 Flutter 테스트 41개 + 지도 생명주기 2개 | 43개 통과 |
| Python HTTP 테스트 | 기존 10개 통과 |
| Android API 36 전용 AVD — Local 기본 흐름 | 목록·상세·복귀, 지도·마커, 성공·실패·타임아웃, 오프라인 차단, 차량 격리 통과 |
| Android — Local 보충 | ID 검색, 상세를 닫은 뒤 명령 완료, 재진입 시 냉동기 상태 반영 통과 |
| Android — 지도 오류·재시도 | 잘못된 이미지 주입 → 오류 표시 → 정상 이미지로 재시도 통과. 실제 통신 단절과 구분 |
| Android — Remote | 목록·상세 HTTP 조회, 명령 성공·실패·불명확 결과, 결과 확인 전 차단, 요청 ID 조회 뒤 버튼 재활성화, 화면 재진입·차량 격리·오프라인 차단 통과 |
| Android — 실제 API 장애·복구 | 테스트 드라이버가 서버를 503 → 종료 → 정상 상태로 전환. 앱의 이전 차량 10대 유지, 오류 표시·복구 통과 |
| Android — 실제 백그라운드·복귀 | ADB로 홈 화면 전환 확인. 서버 목록 요청이 6초간 없고 앱 복귀 시 재조회된 것을 호스트 로그와 앱 lifecycle 이벤트로 확인 |
| iPhone 17 Pro / iOS 26.5 Simulator | 지도 수정 후 Local·Remote 통합 테스트 각각 통과. iOS의 OS 수준 백그라운드 전환은 이번 범위에서 미검증 |

핵심 흐름의 Android 검증 대상은 **기존 Pixel 9가 아닌 전용 API 36 AVD**입니다. 이전 실패 실행의 스크린샷은 성공 근거로 사용하지 않았습니다. 최종 통과 실행에서만 별도 경로에 증거를 저장했습니다.

- [Local 지도·명령 성공](screenshots/v1.1-readiness/android-local-success.png), [Local 시간 초과](screenshots/v1.1-readiness/android-local-timeout.png)
- [Remote 성공](screenshots/v1.1-readiness/android-remote-success.png), [결과 확인 필요·중복 차단](screenshots/v1.1-readiness/android-remote-unknown.png)
- [HTTP 503과 이전 데이터](screenshots/v1.1-readiness/android-http503.png), [복구된 목록](screenshots/v1.1-readiness/android-recovered.png)
- [복귀 화면](screenshots/v1.1-readiness/android-background-resumed.png), [서버 요청·백그라운드 관찰 로그](screenshots/v1.1-readiness/remote-host-evidence.txt)

### 테스트 입력과 장애 제어

작은 화면에서 기본 scroll 입력이 지도 pan 영역에 들어가 목록을 이동하지 못했습니다. [scroll_helpers.dart](../integration_test/scroll_helpers.dart)는 지도 밖의 목록 여백에서 스크롤하며 기존 assertion은 유지합니다. [local_readiness_test.dart](../integration_test/local_readiness_test.dart)는 ID 검색과 화면 종료 후 명령 완료를 추가로 확인합니다.

[android_readiness.dart](../test_driver/android_readiness.dart)는 테스트용 Mock API 프로세스와 루프백 제어 서버를 소유합니다. Android 스크린샷 콜백은 실행 중 제어 시점을 보장하지 않으므로, 장애 전환은 별도 테스트 통신으로 동기화합니다. 백그라운드 전환은 먼저 요청에 응답한 뒤 실행하고, 실제 pause/resume 이벤트와 호스트의 확인 결과를 모두 기다립니다. 앱·운영 API에는 장애 제어 endpoint를 추가하지 않았습니다.

```sh
# 설치된 API 36 이미지로 동명 AVD가 없을 때만 생성 (기존 AVD 덮어쓰기 없음)
avdmanager create avd --name FleetBridge_Readiness_API36_20261116 \
  --package 'system-images;android-36;google_apis_playstore;arm64-v8a' --device pixel_6

# 새로 만든 테스트 AVD 실행 예
adb -P 5047 start-server
ANDROID_ADB_SERVER_PORT=5047 emulator \
  -avd FleetBridge_Readiness_API36_20261116 -ports 5660,5661 \
  -no-snapshot -no-audio -no-window -gpu host -feature -Vulkan \
  -memory 2048 -cores 2 -skin 720x1280
adb -P 5047 connect 127.0.0.1:5661
adb -P 5047 -s 127.0.0.1:5661 shell wm density 280

ANDROID_ADB_SERVER_PORT=5047 ADB_SERVER_SOCKET=tcp:127.0.0.1:5047 \
FLEET_TEST_DEVICE=127.0.0.1:5661 FLEET_TEST_API_PORT=8082 \
FLEET_SCREENSHOT_DIR=/tmp/fleetbridge-readiness-remote \
flutter drive --driver=test_driver/android_readiness.dart \
  --target=integration_test/remote_device_test.dart -d 127.0.0.1:5661 \
  --dart-define=FLEET_MODE=remote \
  --dart-define=FLEET_API_URL=http://10.0.2.2:8082 \
  --dart-define=FLEET_READINESS_CONTROL=true
```

이 드라이버는 8082(API)·8083(테스트 제어)의 루프백 포트를 사용하고 종료 시 자신이 띄운 서버를 정리합니다. 이미 사용하는 포트라면 실행하지 않거나 `FLEET_TEST_API_PORT`·`FLEET_TEST_CONTROL_PORT`와 대응하는 dart-define URL을 함께 변경해야 합니다. SDK 경로는 `ANDROID_HOME` 또는 `ANDROID_SDK_ROOT`에서 찾고, 다른 위치는 `FLEET_TEST_ADB`로 지정합니다.

### 남은 한계와 병합 판단

이번 검증은 시뮬레이션 앱과 로컬 Mock API의 동작을 대상으로 합니다. 실제 차량·관제 서버·실물 기기, iOS의 OS 수준 백그라운드 전환, 다양한 이동통신망 전환, 앱·서버 재시작 뒤 명령의 영속 복구는 보장하지 않습니다. 기존 Pixel 9 AVD의 전체 실행도 별도 재확인 대상입니다. 요청 ID는 승인된 메모리 기반 정책을 유지하며 자동 POST 재전송을 하지 않습니다.

병합 판단은 위 검증 결과와 최신 PR CI를 함께 기준으로 합니다. Android 미검증으로 남았던 핵심 Local/Remote 흐름은 전용 API 36 AVD에서 확인했으며, 위 운영·기기 한계는 남겨둡니다. PR 병합과 v1.1 Release 발행은 이 작업에서 수행하지 않습니다.


현재 명시한 시뮬레이션·Mock API 범위에서는 병합 준비가 된 것으로 판단합니다. 최신 CI 성공을 확인한 뒤에도 기존 Pixel 9 및 실물 기기, iOS OS 수준 백그라운드 전환, 영속 명령 복구 등의 한계는 릴리스 설명에 남겨야 합니다. 운영 관제 서비스의 준비 완료를 뜻하지 않습니다.
