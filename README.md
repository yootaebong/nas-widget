# NAS 위젯

집 NAS·맥·PC 의 CPU·메모리·디스크와 서비스 상태를 macOS 바탕화면 위젯으로 보여 주는 작은 앱입니다.
위젯은 HTTP 로 상태 JSON 하나를 읽어 그리기만 합니다 — 수치를 모으는 서버는 직접 준비합니다.

A tiny macOS desktop widget (WidgetKit, SwiftUI) that renders a single status JSON from your home server. UI text is Korean.

## 요구 사항

- macOS 14 이상, Xcode 15 이상
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)
- 아래 형식의 JSON 을 내려주는 HTTP 주소

## 빌드

```sh
cp Local.xcconfig.example Local.xcconfig   # NAS_STATUS_URL 채우기
xcodegen generate
xcodebuild -project NasWidget.xcodeproj -scheme NasWidget -configuration Release -derivedDataPath build build
open build/Build/Products/Release/NasWidget.app
```

앱을 한 번 띄운 뒤 바탕화면 우클릭 → 위젯 편집 → "NAS 위젯" 을 검색해 추가합니다.
서명은 ad-hoc(`CODE_SIGN_IDENTITY: "-"`)이라 개발자 계정 없이 내 맥에서 돌릴 수 있습니다.
번들 ID 접두사(`project.yml` 의 `bundleIdPrefix`)는 원하는 값으로 바꿔도 됩니다.

### 위젯 모양이 안 바뀔 때

번들 버전이 같으면 위젯을 지웠다 다시 놓아도 옛 모양이 나옵니다.
`project.yml` 의 `CURRENT_PROJECT_VERSION` 을 올려 다시 빌드한 뒤 아래를 실행합니다.

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R build/Build/Products/Release/NasWidget.app
pluginkit -a build/Build/Products/Release/NasWidget.app/Contents/PlugIns/NasWidgetExtension.appex
killall chronod
```

## 설정 (`Local.xcconfig`)

| 키 | 필수 | 설명 |
|---|---|---|
| `NAS_STATUS_URL` | ✅ | 상태 JSON 주소 |
| `DASHBOARD_URL` | | "대시보드 열기" 버튼·위젯 탭으로 열 주소. 비우면 버튼이 사라짐 |

xcconfig 에서 `//` 는 주석이라 URL 은 `http:/$()/host:port/path` 처럼 씁니다.

## 상태 JSON 형식

예시는 [`status.example.json`](status.example.json) 에 있습니다.

| 필드 | 타입 | 설명 |
|---|---|---|
| `time` | int | 수집 시각(유닉스 초) |
| `systems[]` | `{name, up, cpu, mem, disk}` | 기기별 상태. `cpu`·`mem`·`disk` 는 0~100 정수(%). 70 이상 노랑, 90 이상 빨강. 작은 위젯은 첫 기기의 디스크를 그림 |
| `services[]` | `{name, ok, value?}` | 서비스 상태. `value` 는 정상일 때 옆에 보일 글자(예: `"56ms"`) |
| `firing` | int? | 울리는 알림 수. 없으면 "알림 모름" |
| `firing_names` | string[]? | 울리는 알림 이름 |
| `relay_connections` | int? | 있으면 "relay 연결" 줄로 표시 |
| `containers[]` | `{name, mem_mb}`? | 메모리 상위 컨테이너 |

위젯은 5분마다 새로 읽고, 요청 타임아웃은 20초입니다.
서버는 무엇이든 됩니다 — 예를 들어 [Beszel](https://github.com/henrygd/beszel) 허브 API 와 Prometheus 결과를 모아 위 형식으로 내려주는 작은 HTTP 서버면 충분합니다.

## 보안 메모

- 앱은 샌드박스 안에서 네트워크 클라이언트 권한만 씁니다.
- 내부망 NAS 의 `http://` 주소를 읽으려고 `NSAllowsArbitraryLoads` 를 켜 두었습니다. 상태 주소를 인터넷에 열 거라면 HTTPS 와 인증을 붙이세요.
- 상태 주소에 비밀 경로를 쓴다면 `Local.xcconfig` 에만 두세요 — 이 파일은 `.gitignore` 에 들어 있습니다.

## 라이선스

[MIT](LICENSE)
