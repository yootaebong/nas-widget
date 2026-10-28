# NAS 위젯

집 NAS·맥·PC 의 CPU·메모리·디스크와 서비스 상태를 macOS 바탕화면 위젯으로 보여 주는 작은 앱입니다.
위젯은 HTTP 로 상태 JSON 하나를 읽어 그리기만 합니다. 그 JSON 을 만드는 서버는 [`server/`](server/) 에 도커로 들어 있습니다.

A tiny macOS desktop widget (WidgetKit, SwiftUI) that renders a single status JSON from your home server, plus a Docker server that builds that JSON from Beszel. UI text is Korean.

> 처음이면 [처음 쓰는 분을 위한 안내](#처음-쓰는-분을-위한-안내) 부터 보세요. 세 단계, 15분 정도 걸립니다.

## 처음 쓰는 분을 위한 안내

### 어떻게 돌아가나요

```
 [맥·NAS·PC 마다]            [NAS(또는 늘 켜 둔 컴퓨터) 한 대]              [내 맥]
 Beszel 에이전트  ──수치──▶  Beszel 허브 ──▶ 상태 서버(server/)  ──JSON──▶  NAS 위젯
```

- **Beszel 에이전트**: 기기마다 하나씩 깔아 CPU·메모리·디스크·온도를 재는 작은 프로그램입니다.
- **Beszel 허브**: 에이전트들이 보낸 수치를 모아 두는 곳입니다. 웹 화면에서 기기를 붙이고 알림을 정합니다.
- **상태 서버**: 허브의 수치와 "웹사이트가 살아 있나" 같은 확인 결과를 위젯이 읽는 JSON 하나로 묶어 줍니다.
- **위젯**: 그 JSON 을 5분마다 읽어 바탕화면에 그립니다.

허브와 상태 서버는 [`server/compose.yaml`](server/compose.yaml) 하나로 같이 뜹니다. 그래서 할 일은 세 가지입니다.

### 준비물

- 늘 켜 둔 컴퓨터 한 대(NAS·홈서버·미니 PC) + 거기에 **Docker**
  - 시놀로지는 패키지 센터에서 **Container Manager** 를 설치하고, 제어판 → 터미널에서 SSH 를 켜 둡니다.
- 위젯을 놓을 **macOS 14 이상**의 맥
- 맥과 서버가 같은 집 네트워크에 있거나, 밖에서도 보려면 [Tailscale](https://tailscale.com) 같은 VPN

### 1단계 — 서버 띄우기 (NAS 에서, 약 5분)

1. 서버에 SSH 로 들어가 이 저장소를 받습니다. `git` 이 없으면 GitHub 에서 "Code → Download ZIP" 으로 받아 `server` 폴더만 NAS 에 올려도 됩니다.
   ```sh
   git clone https://github.com/yootaebong/nas-widget.git
   cd nas-widget/server
   ```
2. 설정 파일을 만들고, 위젯이 쓸 **토큰**(비밀번호 같은 긴 글자)을 하나 만듭니다.
   ```sh
   cp config.example.toml config.toml
   openssl rand -hex 24
   ```
   나온 글자를 `config.toml` 맨 위 `token = ""` 의 따옴표 안에 붙여 넣습니다. 이 값은 3단계에서 위젯에도 넣으니 적어 두세요.
3. 띄웁니다. 시놀로지는 앞에 `sudo` 를 붙입니다.
   ```sh
   docker compose up -d
   ```

### 2단계 — 기기 붙이기 (Beszel, 기기당 약 2분)

1. NAS 에서 브라우저로 `http://localhost:8090` 을 엽니다. 처음 들어온 사람이 관리자 계정을 만듭니다.
   - 다른 컴퓨터에서 열려면 `compose.yaml` 의 `127.0.0.1:8090:8090` 에서 `127.0.0.1` 을 NAS 의 내부 IP 로 바꾸고 `docker compose up -d` 를 다시 합니다. 계정을 만든 뒤에는 되돌려 두는 편이 안전합니다.
2. 오른쪽 위 **"시스템 추가"** 를 누르고 기기 이름(위젯에 보일 이름)을 적습니다. 화면에 나온 설치 명령을 그 기기의 터미널에 붙여 넣으면 됩니다. 맥·윈도우·리눅스·NAS 모두 됩니다.
3. 방금 만든 Beszel **계정(이메일·비밀번호)** 을 `config.toml` 의 `[beszel]` 칸에 적고, 서버를 다시 띄웁니다. 설정은 서버가 뜰 때만 읽습니다.
   ```sh
   docker compose restart nas-widget-server
   ```
4. 확인: 브라우저나 터미널에서 아래 주소가 기기 목록을 돌려주면 서버는 끝입니다.
   ```sh
   curl -H "Authorization: Bearer <토큰>" http://<NAS IP>:8080/status
   ```

서비스 줄(웹사이트·DB 가 살아 있는지)을 보고 싶으면 `config.toml` 의 `[[services]]` 예시를 내 주소로 바꾸고 다시 `restart` 합니다. 필요 없으면 지웁니다.

### 3단계 — 맥에 위젯 놓기 (약 2분, Xcode 필요 없음)

1. [Releases](https://github.com/yootaebong/nas-widget/releases/latest) 에서 `NasWidget.zip` 을 받아 압축을 풀고, `NasWidget.app` 을 **응용 프로그램** 폴더로 옮깁니다.
2. 터미널을 열어 아래 한 줄을 붙여 넣습니다. 애플 개발자 서명이 없는 앱이라, 이걸 안 하면 "손상되었기 때문에 열 수 없습니다" 가 뜹니다(실제로 손상된 건 아닙니다).
   ```sh
   xattr -cr /Applications/NasWidget.app
   ```
3. 앱을 엽니다. 창에 상태 주소(`http://<NAS IP>:8080/status`)와 토큰을 넣고 **"연결 시험"** 을 눌러 수치가 나오는지 봅니다.
4. 바탕화면 빈 곳을 우클릭 → **위젯 편집** → "NAS 위젯" 을 검색해 원하는 크기를 끌어다 놓습니다.
5. 놓은 위젯을 우클릭 → **"위젯 편집"** → 같은 상태 주소와 토큰을 넣습니다. 앱 창의 칸은 시험용이라 위젯에는 따로 넣어야 합니다.

위젯 크기별로 보이는 것:
- **작게**: 첫 기기의 디스크 사용량 + 알림
- **중간**: 서비스 상태 + 메모리 많이 쓰는 컨테이너
- **크게**: 기기별 CPU·메모리·디스크·온도 + 서비스 + 컨테이너

숫자 색은 70% 이상 노랑, 90% 이상 빨강입니다(온도는 75°·90°). 바탕화면 위젯이 흐린(단색) 모드면 색이 안 보일 수 있습니다.

### 잘 안 될 때

| 보이는 것 | 확인할 것 |
|---|---|
| 위젯에 "위젯 편집에서 상태 주소를 넣어 주세요" | 3단계 5번 — 위젯 자체에 주소를 넣었는지 |
| "토큰이 맞지 않아요" | 위젯 토큰과 `config.toml` 의 `token` 이 같은지(앞뒤 공백 없이) |
| "NAS 에 연결 못 함" | 맥에서 `curl http://<NAS IP>:8080/health` 가 `ok` 인지. 밖이면 Tailscale 이 켜져 있는지 |
| 기기 목록이 비어 있음 | `config.toml` 의 Beszel 이메일·비밀번호, 고친 뒤 `restart` 했는지. 기기를 등록한 바로 그 계정이어야 합니다 |
| 서버가 바로 꺼짐 | `docker compose logs nas-widget-server` — 토큰이 비었거나, `config.toml` 오타, 권한(`chmod 644 config.toml`) 문제를 한국어로 알려 줍니다 |
| 앱을 새 버전으로 바꿨는데 위젯 모양이 그대로 | 위젯을 지우고 다시 놓습니다. 그래도 그대로면 로그아웃했다가 다시 로그인 |

### 위젯만 쓰고 서버는 직접 만들 때

위젯은 아래 [상태 JSON 형식](#상태-json-형식) 만 맞으면 어떤 서버든 읽습니다. 토큰을 넣으면 `Authorization: Bearer <토큰>` 헤더로 보냅니다.

## 상태 서버 설정 더 보기

- 모든 설정 키는 [`server/config.example.toml`](server/config.example.toml) 에 주석으로 설명돼 있습니다.
- 서비스 확인은 `http`(응답 코드 400 미만이면 정상)·`tcp`(포트가 열리면 정상)·`prometheus`(쿼리 결과가 1 이면 정상) 세 가지입니다.
- Prometheus 가 있으면 `[prometheus]` 를 켜서 그쪽 알림(`ALERTS`)과 컨테이너 메모리(cAdvisor)도 보여 줄 수 있습니다.
- 비밀번호를 파일에 두기 싫으면 환경 변수 `TOKEN`·`BESZEL_PASSWORD` 로 넣을 수 있습니다(`compose.yaml` 주석 참고).
- 서버 컨테이너는 root 가 아닌 사용자, 읽기 전용 파일 시스템으로 돕니다.

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
