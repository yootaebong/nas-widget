# 서버 상태 위젯 (nas-widget)

집 서버·맥·PC 의 CPU·메모리·디스크와 서비스 상태를 macOS 바탕화면 위젯으로 보여 주는 작은 앱입니다.
위젯은 HTTP 로 상태 JSON 하나를 읽어 그리기만 합니다. 그 JSON 을 만드는 서버는 [`server/`](server/) 에 도커로 들어 있습니다.

A tiny macOS desktop widget (WidgetKit, SwiftUI) that renders a single status JSON from your home server, plus a Docker server that builds that JSON from Beszel. UI text is Korean.

> 처음이면 [처음 쓰는 분을 위한 안내](#처음-쓰는-분을-위한-안내) 부터 보세요. 세 단계, 15분 정도 걸립니다.

## 처음 쓰는 분을 위한 안내

### 어떻게 돌아가나요

```
 [맥·PC·서버 마다]           [중앙 서버 한 대 (늘 켜 둔 컴퓨터)]            [내 맥]
 Beszel 에이전트  ──수치──▶  Beszel 허브 ──▶ 상태 서버(server/)  ──JSON──▶  위젯
```

- **Beszel 에이전트**: 기기마다 하나씩 깔아 CPU·메모리·디스크·온도를 재는 작은 프로그램입니다.
- **Beszel 허브**: 에이전트들이 보낸 수치를 모아 두는 곳입니다. 웹 화면에서 기기를 붙이고 알림을 정합니다.
- **상태 서버**: 허브의 수치와 "웹사이트가 살아 있나" 같은 확인 결과를 위젯이 읽는 JSON 하나로 묶어 줍니다.
- **위젯**: 그 JSON 을 5분마다 읽어 바탕화면에 그립니다.

허브와 상태 서버는 [`server/compose.yaml`](server/compose.yaml) 하나로 같이 뜹니다. 그래서 할 일은 세 가지입니다.

### 준비물

- **중앙 서버**: 늘 켜 둔 컴퓨터 한 대(NAS·홈서버·미니 PC·안 쓰는 노트북 무엇이든) + 거기에 **Docker**. 이 안내에서 "중앙 서버" 는 이 컴퓨터를 말합니다
  - 시놀로지는 패키지 센터에서 **Container Manager** 를 설치하고, 제어판 → 터미널에서 SSH 를 켜 둡니다.
- 위젯을 놓을 **macOS 14 이상**의 맥
- 맥과 중앙 서버가 **같은 집 네트워크**(같은 공유기)에 있으면 됩니다. 밖에서도 보고 싶으면 [밖에서도 보려면](#밖에서도-보려면) 을 참고하세요

### 1단계 — 중앙 서버에 띄우기 (약 5분)

1. 중앙 서버에 SSH 로 들어가(또는 그 컴퓨터의 터미널을 열어) 이 저장소를 받습니다. `git` 이 없으면 GitHub 에서 "Code → Download ZIP" 으로 받아 `server` 폴더만 중앙 서버에 올려도 됩니다.
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
3. 상태 서버를 열 IP 로 중앙 서버의 **집 안 IP**(예: `192.168.0.10`)를 넣습니다. 도커는 방화벽을 우회하므로 모든 네트워크(`0.0.0.0`)에 열지 않게 해 두었습니다.
   ```sh
   cp .env.example .env      # LISTEN_IP= 를 중앙 서버의 집 안 IP 로 고치기
   ```
   집 안 IP 는 리눅스·시놀로지에서 `ip -4 addr`, 맥에서 `ipconfig getifaddr en0` 으로 봅니다(보통 `192.168.` 으로 시작). 시놀로지는 제어판 → 네트워크 → 네트워크 인터페이스에도 나옵니다.
4. 띄웁니다. 시놀로지는 앞에 `sudo` 를 붙입니다.
   ```sh
   docker compose up -d
   ```

### 2단계 — 기기 붙이기 (Beszel, 기기당 약 2분)

1. 중앙 서버에서 브라우저로 `http://localhost:8090` 을 엽니다. 처음 들어온 사람이 관리자 계정을 만듭니다.
   - 다른 컴퓨터에서 열려면 `compose.yaml` 의 `127.0.0.1:8090:8090` 에서 `127.0.0.1` 을 중앙 서버의 내부 IP 로 바꾸고 `docker compose up -d` 를 다시 합니다. 계정을 만든 뒤에는 되돌려 두는 편이 안전합니다.
2. 오른쪽 위 **"시스템 추가"** 를 누르고 기기 이름(위젯에 보일 이름)을 적습니다. 화면에 나온 설치 명령을 그 기기의 터미널에 붙여 넣으면 됩니다. 맥·윈도우·리눅스·NAS 모두 됩니다(중앙 서버 자신도 붙이면 위젯에 나옵니다).
3. 방금 만든 Beszel **계정(이메일·비밀번호)** 을 `config.toml` 의 `[beszel]` 칸에 적고, 서버를 다시 띄웁니다. 설정은 서버가 뜰 때만 읽습니다.
   ```sh
   docker compose restart nas-widget-server
   ```
4. 확인: 브라우저나 터미널에서 아래 주소가 기기 목록을 돌려주면 서버는 끝입니다.
   ```sh
   curl -H "Authorization: Bearer <토큰>" http://<중앙 서버 IP>:8080/status
   ```

서비스 줄(웹사이트·DB 가 살아 있는지)을 보고 싶으면 `config.toml` 의 `[[services]]` 예시를 내 주소로 바꾸고 다시 `restart` 합니다. 필요 없으면 지웁니다.

### 3단계 — 맥에 위젯 놓기 (약 2분, Xcode 필요 없음)

1. [Releases](https://github.com/yootaebong/nas-widget/releases/latest) 에서 `NasWidget.zip` 과 `NasWidget.zip.sha256` 을 같은 폴더(보통 "다운로드")에 받습니다.
2. 받은 파일을 확인합니다. 어느 쪽이든 실패하면 열지 말고 지우세요.
   ```sh
   cd ~/Downloads
   shasum -a 256 -c NasWidget.zip.sha256     # OK — 다운로드가 깨지지 않았는지
   ```
   이 저장소의 GitHub Actions 가 만든 파일이 맞는지까지 보려면 [GitHub CLI](https://cli.github.com)(`brew install gh`)로 출처 증명을 확인합니다. 해시 파일은 zip 과 같은 곳에서 오니 바꿔치기까지는 못 잡지만, 이건 잡습니다.
   ```sh
   gh attestation verify NasWidget.zip -R yootaebong/nas-widget
   ```
3. 압축을 풀고 `NasWidget.app` 을 **응용 프로그램** 폴더로 옮긴 뒤, 다운로드 표시만 지웁니다. 애플 개발자 서명이 없는 앱이라, 이걸 안 하면 "손상되었기 때문에 열 수 없습니다" 가 뜹니다(실제로 손상된 건 아닙니다). 2번 확인을 마친 파일에만 하세요.
   ```sh
   xattr -dr com.apple.quarantine /Applications/NasWidget.app
   ```
4. 앱을 엽니다. 창에 상태 주소(`http://<중앙 서버 IP>:8080/status`)와 토큰을 넣고 **"연결 시험"** 을 눌러 수치가 나오는지 봅니다.
5. 바탕화면 빈 곳을 우클릭 → **위젯 편집** → "서버 상태" 를 검색해 원하는 크기를 끌어다 놓습니다.
5. 놓은 위젯을 우클릭 → **"위젯 편집"** → 같은 상태 주소와 토큰을 넣습니다. 앱 창의 칸은 시험용이라 위젯에는 따로 넣어야 합니다.

위젯 크기별로 보이는 것:
- **작게**: 첫 기기의 디스크 사용량 + 알림
- **중간**: 서비스 상태 + 메모리 많이 쓰는 컨테이너
- **크게**: 기기별 CPU·메모리·디스크·온도 + 서비스 + 컨테이너

숫자 색은 70% 이상 노랑, 90% 이상 빨강입니다(온도는 75°·90°). 바탕화면 위젯이 흐린(단색) 모드면 색이 안 보일 수 있습니다.

### 밖에서도 보려면

기본은 같은 집 네트워크입니다. 집 밖(회사·카페)에서도 위젯을 보려면 셋 중 하나를 고릅니다.

| 방법 | 이런 분께 | 위젯에 넣는 주소 |
|---|---|---|
| **Tailscale**(가장 쉬움) | 설정 없이 바로 쓰고 싶을 때. 중앙 서버와 맥에 앱을 깔고 같은 계정으로 로그인 | `http://<중앙 서버 Tailscale IP>:8080/status` (100.x.y.z) |
| **다른 VPN** — WireGuard·ZeroTier·시놀로지 VPN Server | 이미 쓰는 VPN 이 있을 때 | `http://<VPN 안 IP>:8080/status` |
| **https 로 열기** — 시놀로지 리버스 프록시 + Let's Encrypt, Cloudflare Tunnel 등 | VPN 을 켜지 않고 보고 싶을 때 | `https://status.내도메인/status` |

- **Tailscale**: 중앙 서버에서 `tailscale ip -4` 로 IP 를 보고, `.env` 의 `LISTEN_IP` 를 그 IP 로 바꾼 뒤 `docker compose up -d` 를 다시 합니다. 집 안에서도 그 주소로 됩니다.
  - **시놀로지**의 Tailscale 패키지는 Tailscale IP 를 장치로 만들지 않아 그 IP 에는 열 수 없습니다(`ip -4 addr` 에 100.x 가 안 보이면 이 경우). 대신 `LISTEN_IP=127.0.0.1` 로 두면 Tailscale 로 들어온 연결이 그쪽으로 넘어옵니다. 이때는 집 안 IP 로는 안 보이니, 맥에서도 Tailscale 을 켜 두세요.
- **다른 VPN**: 보통 10.x·172.16~31.x·192.168.x 주소를 써서 위젯이 http 를 그대로 받습니다. 그 밖의 주소를 쓰는 VPN 이면 https 방법을 쓰세요. `LISTEN_IP` 는 VPN 이 중앙 서버에 준 IP 로 바꿉니다.
- **https 로 열기**: 인터넷에 열리므로 토큰이 유일한 문입니다 — 긴 토큰을 쓰세요. 프록시는 `http://<LISTEN_IP>:8080` 으로 넘기면 됩니다. Cloudflare Access 처럼 앞에 로그인 화면을 두는 방식은 위젯이 로그인을 못 해서 쓸 수 없습니다.

### 잘 안 될 때

| 보이는 것 | 확인할 것 |
|---|---|
| 위젯에 "위젯 편집에서 상태 주소를 넣어 주세요" | 3단계 5번 — 위젯 자체에 주소를 넣었는지 |
| "토큰이 맞지 않아요" | 위젯 토큰과 `config.toml` 의 `token` 이 같은지(앞뒤 공백 없이) |
| "중앙 서버에 연결 못 함" | 맥에서 `curl http://<중앙 서버 IP>:8080/health` 가 `ok` 인지. 맥이 같은 공유기에 붙어 있는지(밖이면 VPN 이 켜져 있는지) |
| "공개 주소는 https:// 로" | `http://` 는 집 안·VPN 의 IP 주소(192.168.x, 10.x, 172.16~31.x, Tailscale 100.x)나 `.local`·점 없는 이름에만 씁니다. 그 밖의 주소는 [밖에서도 보려면](#밖에서도-보려면) 의 https 방법을 쓰세요 |
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
- `http://` 는 집 안·VPN 주소에만 씁니다(ATS `NSAllowsLocalNetworking`). 공개 주소에 http 를 넣으면 위젯이 토큰을 보내지 않고 거절합니다 — 가는 길에 누구나 읽을 수 있어서요.
- 응답은 512KB 까지만 받고, 위젯에 다 못 그리는 항목은 버립니다.
- 위젯 편집에 넣은 주소·토큰은 macOS 위젯 설정에, 앱 창의 값은 앱 설정 파일에 평문으로 저장됩니다(위젯 편집 칸은 가려지지 않습니다). 토큰은 상태 조회 전용이지만, 새었다고 생각되면 `config.toml` 의 `token` 을 바꾸고 `docker compose restart nas-widget-server` 한 뒤 위젯에 새 값을 넣으세요.
- 상태 서버는 Bearer 헤더 토큰만 받습니다(`?token=` 주소 방식은 `allow_query_token = true` 일 때만 — 프록시 로그에 남습니다). 동시 연결 32개, 요청 헤더 15초 제한이 있고, root 가 아닌 사용자·읽기 전용 파일 시스템·권한 없이 돕니다.
- 릴리스는 버전·해시를 고정한 도구로 GitHub Actions 에서만 만들고, 같은 태그의 파일을 덮어쓰지 않습니다. 받은 파일은 위 3단계 2번처럼 확인하세요.
- `Local.xcconfig` 는 `.gitignore` 에 들어 있지만, 넣은 값은 빌드 결과물에 남습니다.

## 라이선스

[MIT](LICENSE)
