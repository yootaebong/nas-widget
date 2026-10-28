# NAS 위젯

집 NAS·맥·PC 의 CPU·메모리·디스크와 서비스 상태를 macOS 바탕화면 위젯으로 보여 주는 작은 앱입니다.
위젯은 HTTP 로 상태 JSON 하나를 읽어 그리기만 합니다. 그 JSON 을 만드는 서버는 [`server/`](server/) 에 도커로 들어 있습니다.

A tiny macOS desktop widget (WidgetKit, SwiftUI) that renders a single status JSON from your home server. UI text is Korean.

## 설치 (Xcode 없이)

macOS 14 이상에서 돕니다.

1. [Releases](https://github.com/yootaebong/nas-widget/releases/latest) 에서 `NasWidget.zip` 을 받아 압축을 풀고 `NasWidget.app` 을 응용 프로그램 폴더에 넣습니다.
2. 처음 한 번은 터미널에서 다운로드 표시를 지웁니다. 애플 개발자 서명이 없는 앱이라 그냥 열면 "손상되었다" 며 열리지 않습니다:
   ```sh
   xattr -cr /Applications/NasWidget.app
   ```
3. 앱을 한 번 엽니다. 창에 상태 주소를 넣고 "연결 시험" 으로 수치가 보이는지 확인합니다.
4. 바탕화면 우클릭 → 위젯 편집 → "NAS 위젯" 을 검색해 놓습니다.
5. 놓은 위젯을 우클릭 → "위젯 편집" → **상태 주소**(필요하면 토큰·대시보드 주소)를 넣습니다.

직접 빌드해 쓰던 위젯 위에 배포판을 덮으면 위젯이 "주소를 넣어 주세요" 로 바뀝니다 — 5번처럼 주소를 넣으면 됩니다.
상태 주소를 내려주는 서버가 없으면 아래 [상태 서버](#상태-서버-도커) 를 먼저 띄웁니다.

## 상태 서버 (도커)

[`server/`](server/) 에 상태 JSON 을 만들어 주는 작은 서버가 있습니다(파이썬 표준 라이브러리만 씀).

- **기기 수치**는 [Beszel](https://github.com/henrygd/beszel) 허브에서 가져옵니다. Beszel 은 기기마다 에이전트 한 줄로 깔고 CPU·메모리·디스크·온도를 모아 주는 도구입니다.
- **서비스 줄**은 설정에 적은 주소를 서버가 직접 확인합니다(HTTP·TCP). Prometheus 가 있으면 쿼리로도 됩니다.
- **알림 수**는 Beszel 알림(+ Prometheus `ALERTS`)에서, **컨테이너 메모리**는 Prometheus(cAdvisor)에서 가져옵니다 — 둘 다 선택입니다.

1. 설정 파일을 만들고 토큰을 넣습니다(토큰이 비면 서버가 뜨지 않습니다).
   ```sh
   cd server
   cp config.example.toml config.toml
   openssl rand -hex 24      # 나온 값을 config.toml 의 token 에
   docker compose up -d
   ```
2. Beszel 이 처음이면 서버에서 `http://localhost:8090` 을 열어 계정을 만들고, "시스템 추가" 로 기기를 붙입니다(화면에 에이전트 설치 명령이 나옵니다). 이미 Beszel 이 있으면 `compose.yaml` 에서 `beszel` 서비스를 지우고 `[beszel] url` 을 그 주소로 바꿉니다.
3. 그 계정을 `config.toml` 의 `[beszel] email`·`password` 에 적고 서버를 다시 띄웁니다 — 설정은 뜰 때만 읽습니다.
   ```sh
   docker compose restart nas-widget-server
   ```
4. 서비스 줄(`[[services]]`)은 예시를 지우고 내 주소로 바꿉니다.

위젯에는 `http://<서버>:8080/status` 와 `config.toml` 의 토큰을 넣습니다.
서버는 무엇으로 만들어도 됩니다 — 아래 형식의 JSON 만 내려주면 됩니다.

## 직접 빌드 (개발용)

- macOS 14 이상, Xcode 15 이상, [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

```sh
cp Local.xcconfig.example Local.xcconfig   # 값은 비워 둬도 된다
xcodegen generate
xcodebuild -project NasWidget.xcodeproj -scheme NasWidget -configuration Release -derivedDataPath build build
open build/Build/Products/Release/NasWidget.app
```

서명은 ad-hoc(`CODE_SIGN_IDENTITY: "-"`)이라 개발자 계정 없이 내 맥에서 돌릴 수 있습니다.
번들 ID 접두사(`project.yml` 의 `bundleIdPrefix`)는 원하는 값으로 바꿔도 됩니다.
릴리스는 `v*` 태그를 push 하면 GitHub Actions 가 `NasWidget.zip` 을 만들어 올립니다(`.github/workflows/release.yml`).

### 위젯 모양이 안 바뀔 때

번들 버전이 같으면 위젯을 지웠다 다시 놓아도 옛 모양이 나옵니다.
`project.yml` 의 `CURRENT_PROJECT_VERSION` 을 올려 다시 빌드한 뒤 아래를 실행합니다.

```sh
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f -R build/Build/Products/Release/NasWidget.app
pluginkit -a build/Build/Products/Release/NasWidget.app/Contents/PlugIns/NasWidgetExtension.appex
killall chronod
```

### 기본값 (`Local.xcconfig`)

위젯 편집 칸이 비었을 때 쓰는 값입니다. 배포판은 모두 비어 있습니다.

| 키 | 설명 |
|---|---|
| `NAS_STATUS_URL` | 상태 JSON 주소 |
| `NAS_STATUS_TOKEN` | 상태 서버 토큰(`Authorization: Bearer` 로 보냄) |
| `DASHBOARD_URL` | "대시보드 열기" 버튼·위젯 탭으로 열 주소. 비우면 버튼이 사라짐 |

xcconfig 에서 `//` 는 주석이라 URL 은 `http:/$()/host:port/path` 처럼 씁니다.
**여기 넣은 값은 빌드된 앱의 Info.plist 에 평문으로 들어갑니다** — 비밀 값을 넣었다면 빌드한 앱을 남에게 주지 마세요.

## 상태 JSON 형식

예시는 [`status.example.json`](status.example.json) 에 있습니다.

| 필드 | 타입 | 설명 |
|---|---|---|
| `time` | int | 수집 시각(유닉스 초) |
| `systems[]` | `{name, up, cpu, mem, disk, temp?}` | 기기별 상태. `cpu`·`mem`·`disk` 는 0~100 정수(%). 70 이상 노랑, 90 이상 빨강. `temp` 는 가장 뜨거운 센서 °C 정수(없거나 null 이면 "-"), 75 이상 노랑, 90 이상 빨강. 작은 위젯은 첫 기기의 디스크를 그림 |
| `services[]` | `{name, ok, value?}` | 서비스 상태. `value` 는 정상일 때 옆에 보일 글자(예: `"56ms"`) |
| `firing` | int? | 울리는 알림 수. 없으면 "알림 모름" |
| `firing_names` | string[]? | 울리는 알림 이름 |
| `relay_connections` | int? | 있으면 "relay 연결" 줄로 표시(직접 만든 서버용 — `server/` 는 내지 않음) |
| `containers[]` | `{name, mem_mb}`? | 메모리 상위 컨테이너 |

위젯은 5분마다 새로 읽고, 요청 타임아웃은 20초입니다.

## 보안 메모

- 앱은 샌드박스 안에서 네트워크 클라이언트 권한만 씁니다.
- 내부망 NAS 의 `http://` 주소를 읽으려고 `NSAllowsArbitraryLoads` 를 켜 두었습니다. 상태 주소를 인터넷에 열 거라면 HTTPS 와 인증을 붙이세요.
- 위젯 편집에 넣은 주소·토큰은 macOS 위젯 설정에 저장됩니다. 상태 서버 토큰은 남과 공유하지 마세요.
- `Local.xcconfig` 는 `.gitignore` 에 들어 있지만, 넣은 값은 빌드 결과물에 남습니다.

## 라이선스

[MIT](LICENSE)
