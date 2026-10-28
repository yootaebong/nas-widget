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
   - 중앙 서버에 화면이 없으면 다른 컴퓨터에서 엽니다. `.env` 에 `BESZEL_LISTEN_IP=<중앙 서버 집 안 IP>` 를 넣고 `docker compose up -d` 를 다시 한 뒤 `http://<중앙 서버 IP>:8090` 으로 들어가세요. 처음 들어온 사람이 관리자가 되니 계정은 바로 만듭니다.
2. 오른쪽 위 **"시스템 추가"** 를 누르고 기기 이름(위젯에 보일 이름)을 적습니다. 화면에 나온 설치 명령을 그 기기에 붙여 넣으면 됩니다. 볼 기기마다 한 번씩 하면 위젯·웹 화면에 모두 나옵니다(중앙 서버 자신도 붙이면 나옵니다).
   - **맥·리눅스·NAS**: 터미널에 붙여 넣습니다.
   - **윈도우**: 창에서 Windows 용 명령을 골라 **관리자 권한 PowerShell** 에 붙여 넣습니다. 서비스로 깔려 재부팅해도 다시 켜집니다([Beszel 설치 안내](https://beszel.dev/guide/agent-installation)). 윈도우는 CPU 온도가 안 나오는 경우가 많습니다.
3. 방금 만든 Beszel **계정(이메일·비밀번호)** 을 `config.toml` 의 `[beszel]` 칸에 적고, 서버를 다시 띄웁니다. 설정은 서버가 뜰 때만 읽습니다.
   ```sh
   docker compose restart nas-widget-server
   ```
4. 확인: 브라우저나 터미널에서 아래 주소가 기기 목록을 돌려주면 서버는 끝입니다.
   ```sh
   curl -H "Authorization: Bearer <토큰>" http://<중앙 서버 IP>:8080/status
   ```

`config.toml` 의 `[[services]]` 예시(웹·DB)는 일단 지워도 됩니다. 위젯 아래 칸 채우는 법은 [4단계](#4단계선택--위젯-아래-칸-채우기) 에 있습니다.

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
4. 앱을 엽니다. 창에 상태 주소(`http://<중앙 서버 IP>:8080/status`)와 토큰을 넣고 **"연결 시험"** 을 눌러 수치가 나오는지 봅니다. 통과하면 "저장됨" 이 뜨고, 위젯이 이 값을 그대로 씁니다.
5. 바탕화면 빈 곳을 우클릭 → **위젯 편집** → "서버 상태" 를 검색해 원하는 크기를 끌어다 놓습니다. 위젯에 따로 넣을 것은 없습니다.
   - 위젯마다 다른 서버를 보고 싶을 때만 그 위젯을 우클릭 → **"위젯 편집"** 에 주소·토큰을 넣습니다. 주소를 넣은 위젯은 그 칸의 값만 씁니다(주소 칸이 비어 있으면 토큰만 넣어도 앱 창 값을 씁니다).

위젯 크기별로 보이는 것:
- **작게**: 첫 기기의 디스크 사용량 + 알림
- **중간**: 서비스 상태 + 메모리 많이 쓰는 컨테이너
- **크게**: 기기별 CPU·메모리·디스크·온도 + 서비스 + 컨테이너

숫자 색은 70% 이상 노랑, 90% 이상 빨강입니다(온도는 75°·90°). 바탕화면 위젯이 흐린(단색) 모드면 색이 안 보일 수 있습니다.

### 4단계(선택) — 위젯 아래 칸 채우기

중간·큰 위젯의 기기 수치 아래에는 세 가지가 나옵니다. 아무것도 안 해도 위젯은 돌아가고, 채우지 않은 칸은 안 보입니다.

```
⚠ 알림 2건 · 중앙 서버 디스크, 맥북 온도      ← 알림 띠 (울리는 알림이 있을 때만)
 기기 수치 …
 웹사이트  ● 56ms     공유기  ● 3ms          ← 서비스 줄 (초록 = 정상, 빨강 = 죽음)
 게임 서버 ● 1ms      방문자  ● 1,234명       ← 값 줄 (회색 = 판정 없이 값만)
 도커 메모리 상위  immich 1.8GB · redis 389MB ← 컨테이너 칸
```

#### 서비스 줄 — "이거 살아 있나?" 를 한 줄씩

`config.toml` 의 `[[services]]` 하나가 한 줄입니다. 예시의 "웹"·"DB" 를 지우고 내 것을 적습니다. 확인 방법은 둘 중 하나를 고릅니다(값을 그대로 보고 싶으면 아래 [값 줄](#값-줄--숫자글자를-그대로-v17)).

- **웹 화면이 있는 것**(웹사이트·NAS 관리 화면·공유기·사진 앱 등) → `http = "주소"`. 열리면 초록, 걸린 시간이 옆에 나옵니다.
- **웹 화면이 없는 것**(DB·게임 서버·SSH 등) → `tcp = "IP:포트"`. 포트가 열려 있으면 초록입니다.

```toml
[[services]]
name = "웹사이트"
http = "https://내도메인.com"

[[services]]
name = "공유기"
http = "http://192.168.0.1"

[[services]]
name = "NAS 관리"
http = "https://192.168.0.10:5001"
insecure = true          # 시놀로지 관리 화면처럼 자체 인증서면 넣기

[[services]]
name = "게임 서버"
tcp = "192.168.0.10:25565"
```

- **`localhost`·`127.0.0.1` 은 쓰지 마세요.** 상태 서버는 도커 안에서 돌아서, 거기서 `localhost` 는 중앙 서버가 아니라 도커 상자 자신입니다. 중앙 서버에 있는 것도 **집 안 IP**(예: `192.168.0.10`)로 적습니다.
- 이름은 짧게(한글 4~5자). 큰 위젯은 두 줄씩 나란히 6~8개가 보기 좋습니다.
- 고친 뒤에는 `docker compose restart nas-widget-server`. 위젯은 5분마다 새로 읽습니다(바로 보려면 앱의 "연결 시험").
- 빨강인데 이유를 모르겠으면 `docker compose logs nas-widget-server` 에 "서비스 ○○ 실패" 와 까닭이 남습니다.

#### 값 줄 — 숫자·글자를 그대로 (v1.7~)

"살았나 죽었나" 대신 값 자체를 보고 싶을 때 씁니다. 예: 오늘 방문자 수, 마지막 백업 시각, 남은 할 일 수. 값은 회색으로 보이고, 못 읽으면 빨강 "못 읽음" 이 됩니다.

다른 서비스가 JSON 을 내 주는 주소가 있으면 `json` 에 그 주소, `path` 에 꺼낼 칸을 적습니다. `path` 는 점으로 잇고 목록은 번호(0부터)로 고릅니다.

```toml
# 응답이 {"data": {"visitors": 1234, "backups": [{"last": "03:00"}]}} 일 때
[[services]]
name = "방문자"
json = "http://192.168.0.10:3000/api/stats"
path = "data.visitors"
unit = "명"               # 값 뒤에 붙일 글자(선택). "ms" 만 특별 — 초 단위 값을 ms 로 바꿔 보여 줌

[[services]]
name = "백업"
json = "http://192.168.0.10:3000/api/stats"
path = "data.backups.0.last"
headers = { Authorization = "Bearer API키" }   # API 키가 필요하면(선택)
```

- **기준을 정하면 초록·빨강으로 바뀝니다.** `max = 90` 이면 90 이하일 때 초록·넘으면 빨강(값은 그대로 보임), `min = 1` 이면 1 이상일 때 초록. 숫자는 따옴표 없이 씁니다. 기준이 없으면 회색 값 줄입니다.
- 주소를 브라우저로 열어 보면 JSON 모양을 볼 수 있습니다. 거기서 원하는 숫자까지 칸 이름을 점으로 이으면 `path` 입니다.
- 값은 24자까지 보이고, 숫자는 `1,234` 처럼 쉼표를 넣습니다. 응답이 1MB 를 넘거나 다른 주소로 넘기면(리다이렉트) 못 읽음입니다.
- Prometheus 가 있으면 `prometheus_value = "쿼리"` 만 적어도 값 줄이 됩니다(예: `sum(buzz_ws_connections_active)` → 접속 수).

#### 알림 띠 — 기준을 넘으면 맨 위에 빨갛게

Beszel 웹 화면(`http://<중앙 서버 IP>:8090`)에서 기기 줄의 **종 모양 아이콘**을 눌러 기준을 정합니다. 예: 디스크 90% 넘으면, CPU 온도 80° 넘으면, 기기가 꺼지면. 기준을 넘은 동안 위젯 맨 위에 "알림 N건 · 어떤 알림" 이 뜹니다. 휴대폰·메일로도 받으려면 Beszel 오른쪽 위 설정 → 알림에서 받을 곳(텔레그램·디스코드·메일 등)을 더합니다.

위젯 머리의 작은 글자는 알림 상태입니다. **알림 없음**(초록) = 울리는 것 없음, **알림 모름**(회색) = Beszel 에 못 붙어 알림을 확인 못 함(`config.toml` 의 `[beszel]` 계정 확인).

#### 컨테이너 칸 — 고급, 없어도 됩니다

중앙 서버 도커 컨테이너 가운데 메모리를 가장 많이 쓰는 3개를 보여 줍니다. Prometheus 와 cAdvisor 를 이미 쓰는 분만 `config.toml` 의 `[prometheus]` 주석을 풀고 `containers = true` 로 둡니다. 없으면 이 칸은 안 나옵니다. Prometheus 가 있으면 서비스 줄에 `prometheus = "쿼리"`(결과가 1 이면 초록)도 쓸 수 있습니다 — 예시는 `config.example.toml` 끝에 있습니다.

### 다른 기기에서 보려면 (윈도우·휴대폰·다른 맥)

위젯은 맥 전용이지만, 수치는 중앙 서버에 모여 있으니 어느 기기에서든 볼 수 있습니다.

| 보는 기기 | 방법 |
|---|---|
| **다른 맥** | 3단계를 그 맥에서 그대로 합니다. 상태 주소·토큰은 같은 값을 넣습니다 |
| **윈도우·휴대폰·태블릿** | 브라우저로 **Beszel 웹 화면** `http://<중앙 서버 IP>:8090` 을 엽니다. 기기별 CPU·메모리·디스크 그래프와 알림이 다 나옵니다 |
| **스크립트·다른 프로그램** | 상태 JSON 을 직접 읽습니다(아래) |

Beszel 웹 화면을 다른 기기에서 열려면 한 번만 설정합니다.
1. 관리자 계정을 먼저 만들어 둡니다(2단계 1번). 계정이 없는 채로 열면 같은 네트워크의 누구든 관리자가 될 수 있습니다.
2. 중앙 서버의 `.env` 에 `BESZEL_LISTEN_IP=<중앙 서버 집 안 IP>` 를 넣고 `docker compose up -d` 를 다시 합니다.
3. 윈도우는 브라우저 주소창에, 휴대폰은 브라우저로 열고 "홈 화면에 추가" 하면 앱처럼 씁니다. 로그인은 Beszel 계정으로 합니다.
   - 가족 등 다른 사람에게 보여 줄 땐 관리자 계정을 나눠 주지 말고 계정을 따로 만듭니다. `http://<중앙 서버 IP>:8090/_/`(관리 화면)의 `users` 에서 새 계정을 만들고 role 을 `readonly` 로 두면 보기만 합니다. Beszel 은 기기를 계정별로 보여 주니, 같은 화면의 `systems` 에서 보여 줄 기기를 열어 `users` 칸에 그 계정을 더해 줍니다([Beszel 안내](https://beszel.dev/guide/user-accounts)).

상태 JSON 을 직접 보려면(윈도우 PowerShell 은 `curl` 대신 `curl.exe`):
```sh
curl -H "Authorization: Bearer <토큰>" http://<중앙 서버 IP>:8080/status
```
브라우저 주소창으로는 토큰 헤더를 못 붙여 안 열립니다. 꼭 필요하면 `config.toml` 의 `allow_query_token` 을 켜고 `?token=<토큰>` 을 붙이지만, 토큰이 방문 기록에 남으니 권하지 않습니다.

집 밖에서 볼 때도 같습니다 — 아래 방법으로 연결한 뒤 같은 주소(VPN 이면 VPN IP)로 엽니다. 시놀로지 Tailscale 이면 `BESZEL_LISTEN_IP=127.0.0.1` 그대로 둬도 Tailscale 로는 열립니다.

### 밖에서도 보려면

기본은 같은 집 네트워크입니다. 집 밖(회사·카페)에서도 위젯을 보려면 셋 중 하나를 고릅니다.

| 방법 | 이런 분께 | 위젯에 넣는 주소 |
|---|---|---|
| **Tailscale**(가장 쉬움) | 설정 없이 바로 쓰고 싶을 때. 중앙 서버와 맥에 앱을 깔고 같은 계정으로 로그인 | `http://<중앙 서버 Tailscale IP>:8080/status` (100.x.y.z) |
| **다른 VPN** — WireGuard·ZeroTier·시놀로지 VPN Server | 이미 쓰는 VPN 이 있을 때 | `http://<VPN 안 IP>:8080/status` |
| **https 로 열기** — 시놀로지 리버스 프록시 + Let's Encrypt, Cloudflare Tunnel 등 | VPN 을 켜지 않고 보고 싶을 때 | `https://status.내도메인/status` |

- **Tailscale**: 주소에는 Tailscale IP(100.x) 나 MagicDNS 이름(예: `http://mynas:8080/status`, 점 없는 기기 이름) 둘 다 됩니다. 100.x 는 이 맥에서 Tailscale 이 켜져 있을 때만 받습니다(꺼져 있으면 통신사 망 주소일 수 있어 막음). 중앙 서버에서 `tailscale ip -4` 로 IP 를 보고, `.env` 의 `LISTEN_IP` 를 그 IP 로 바꾼 뒤 `docker compose up -d` 를 다시 합니다. 집 안에서도 그 주소로 됩니다.
  - **시놀로지**의 Tailscale 패키지는 Tailscale IP 를 장치로 만들지 않아 그 IP 에는 열 수 없습니다(`ip -4 addr` 에 100.x 가 안 보이면 이 경우). 대신 `LISTEN_IP=127.0.0.1` 로 두면 Tailscale 로 들어온 연결이 그쪽으로 넘어옵니다. 이때는 집 안 IP 로는 안 보이니, 맥에서도 Tailscale 을 켜 두세요.
- **다른 VPN**: 보통 10.x·172.16~31.x·192.168.x 주소를 써서 위젯이 http 를 그대로 받습니다. 그 밖의 주소를 쓰는 VPN 이면 https 방법을 쓰세요. `LISTEN_IP` 는 VPN 이 중앙 서버에 준 IP 로 바꿉니다.
- **https 로 열기**: 인터넷에 열리므로 토큰이 유일한 문입니다 — 긴 토큰을 쓰세요. 프록시는 `http://<LISTEN_IP>:8080` 으로 넘기면 됩니다. Cloudflare Access 처럼 앞에 로그인 화면을 두는 방식은 위젯이 로그인을 못 해서 쓸 수 없습니다.

### 잘 안 될 때

| 보이는 것 | 확인할 것 |
|---|---|
| 위젯에 "앱을 열어 주소를 넣고 연결 시험을 눌러 주세요" | 3단계 4번 — 앱 창에서 연결 시험이 통과해 "저장됨" 이 떴는지(v1.9~) |
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
- Grafana 알림 규칙을 쓰면 `[grafana]` 를 켜서 울리는 알림을 알림 띠에 더합니다(서비스 계정 토큰 또는 계정·비밀번호).
- 비밀번호를 파일에 두기 싫으면 환경 변수 `TOKEN`·`BESZEL_PASSWORD`·`GRAFANA_PASSWORD` 로 넣을 수 있습니다(`compose.yaml` 주석 참고).
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

위젯 편집 칸도, 앱 창에서 저장한 값도 없을 때 쓰는 값입니다. 배포판은 모두 비어 있습니다.

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
| `services[]` | `{name, ok, value?, info?}` | 서비스 상태. `value` 는 옆에 보일 글자(예: `"56ms"`, v1.7~ 는 `ok: false` 여도 있으면 빨강으로 보임). `info: true` 면 판정 없는 값 줄 — 정상은 회색으로 값만, `ok: false` 는 "못 읽음"(v1.7~, 옛 위젯은 무시하고 초록·"죽음" 으로 그림) |
| `firing` | int? | 울리는 알림 수. 없으면 "알림 모름" |
| `firing_names` | string[]? | 울리는 알림 이름 |
| `relay_connections` | int? | 있으면 "relay 연결" 줄로 표시(직접 만든 서버용 — `server/` 는 내지 않음) |
| `containers[]` | `{name, mem_mb}`? | 메모리 상위 컨테이너 |

위젯은 5분마다 새로 읽고, 요청 타임아웃은 20초입니다.

## 보안 메모

- 앱은 샌드박스 안에서 네트워크 클라이언트 권한만 씁니다.
- `http://` 는 집 안·VPN 주소에만 씁니다. 공개 주소에 http 를 넣으면 위젯이 토큰을 보내지 않고 거절합니다 — 가는 길에 누구나 읽을 수 있어서요. 이 검사는 앱이 직접 합니다(`isPlainHTTPToPublic`) — 이름으로 넣은 주소(`nas`·`nas.local`)는 보내기 전에 실제로 풀리는 IP 가 모두 내부 주소인지 다시 봐서, 공용 와이파이 DNS 가 바깥 IP 를 알려 줘도 토큰을 보내지 않습니다. 애플 ATS 의 "내부망만 허용"은 Tailscale 100.x 를 막아서 ATS 는 모두 허용으로 두었습니다(v1.8~).
- 응답은 512KB 까지만 받고, 위젯에 다 못 그리는 항목은 버립니다.
- 앱 창에서 연결 시험을 통과한 주소·토큰은 `~/Library/Application Support/NasWidget/config.json`(나만 읽기, 600)에, 위젯 편집에 넣은 값은 macOS 위젯 설정에 평문으로 저장됩니다. 앱과 위젯이 둘 다 샌드박스라, 이 폴더 하나만 샌드박스 예외로 열어 나눠 씁니다(앱은 읽기·쓰기, 위젯은 읽기만). 토큰은 상태 조회 전용이지만, 새었다고 생각되면 `config.toml` 의 `token` 을 바꾸고 `docker compose restart nas-widget-server` 한 뒤 앱 창에 새 토큰을 넣고 연결 시험을 누르세요.
- 상태 서버는 Bearer 헤더 토큰만 받습니다(`?token=` 주소 방식은 `allow_query_token = true` 일 때만 — 프록시 로그에 남습니다). 동시 연결 32개, 요청 헤더 15초 제한이 있고, root 가 아닌 사용자·읽기 전용 파일 시스템·권한 없이 돕니다.
- 릴리스는 버전·해시를 고정한 도구로 GitHub Actions 에서만 만들고, 같은 태그의 파일을 덮어쓰지 않습니다. 받은 파일은 위 3단계 2번처럼 확인하세요.
- `Local.xcconfig` 는 `.gitignore` 에 들어 있지만, 넣은 값은 빌드 결과물에 남습니다.

## 라이선스

[MIT](LICENSE)
