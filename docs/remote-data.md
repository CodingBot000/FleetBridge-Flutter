# v1.1 원격 데이터 검증 기록

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
