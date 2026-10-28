"""서버 상태 위젯의 상태 서버.

Beszel 허브·Prometheus·HTTP/TCP 확인 결과를 모아 macOS 위젯이 읽는 상태 JSON 하나로 내려준다.
Python 3.12 표준 라이브러리만 쓴다.

  GET /status  상태 JSON (설정 token 이 있으면 Bearer 헤더 필요, ?token= 은 allow_query_token = true 일 때만)
  GET /health  "ok" (인증 없음)
"""

from __future__ import annotations

import hmac
import json
import logging
import os
import socket
import socketserver
import ssl
import sys
import threading
import time
import tomllib
import urllib.error
import urllib.parse
import urllib.request
from concurrent.futures import ThreadPoolExecutor
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any

DEFAULT_CONFIG_PATH = "/config/config.toml"
DEFAULT_PORT = 8080
DEFAULT_CACHE_SECONDS = 30
DEFAULT_SERVICE_TIMEOUT = 5.0
SOURCE_TIMEOUT = 10.0
AUTH_RETRY_SECONDS = 5.0
BESZEL_PER_PAGE = 200
SERVICE_WORKERS = 12
BYTES_PER_MB = 1048576
CONTAINERS_QUERY = 'topk(3, sum by (name)(container_memory_working_set_bytes{name!=""}))'
PROM_ALERTS_QUERY = 'ALERTS{alertstate="firing"}'
DEFAULT_MAX_CONNECTIONS = 32  # 동시에 붙잡을 수 있는 연결 수. 넘으면 바로 닫는다(env MAX_CONNECTIONS)
REQUEST_TIMEOUT = 10  # 소켓 읽기 한 번의 제한 시간(초)
HEADER_DEADLINE_SECONDS = 15.0  # 요청 줄+헤더를 다 받기까지의 총 제한 시간(1바이트씩 흘리는 연결 차단)
JSON_MAX_BYTES = 1048576  # json 확인이 읽을 응답 최대 크기
VALUE_MAX_CHARS = 24  # 위젯 한 줄에 보일 값 글자 수

log = logging.getLogger("nas-widget-server")

Json = dict[str, Any]


class HttpStatusError(Exception):
    def __init__(self, code: int) -> None:
        super().__init__(f"HTTP {code}")
        self.code = code


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """리다이렉트를 따라가지 않는다 — Beszel 토큰·비밀번호가 다른 주소로 넘어가지 않게. 3xx 는 HTTPError 로 올라온다."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[no-untyped-def]
        return None


_SOURCE_OPENER = urllib.request.build_opener(_NoRedirect)


def http_json(url: str, headers: dict[str, str] | None = None, data: bytes | None = None,
              timeout: float = SOURCE_TIMEOUT) -> Any:
    """Beszel·Prometheus 요청. 리다이렉트는 따라가지 않고 HttpStatusError(3xx) 로 낸다."""
    req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json", **(headers or {})})
    try:
        with _SOURCE_OPENER.open(req, timeout=timeout) as r:
            return json.loads(r.read())
    except urllib.error.HTTPError as e:
        e.close()
        raise HttpStatusError(e.code) from e


# ---------- 설정 ----------

def load_config(path: str | None = None) -> Json:
    path = path or os.environ.get("CONFIG", DEFAULT_CONFIG_PATH)
    try:
        with open(path, "rb") as f:
            cfg = tomllib.load(f)
    except FileNotFoundError:
        log.warning("설정 파일이 없습니다: %s — 빈 설정으로 시작합니다", path)
        cfg = {}
    except IsADirectoryError:
        # config.toml 없이 compose 를 올리면 도커가 그 자리에 빈 폴더를 만든다.
        sys.exit(f"{path} 가 폴더입니다 — 호스트의 빈 config.toml 폴더를 지우고(rm -r config.toml) "
                 "config.example.toml 을 config.toml 로 복사한 뒤 다시 올리세요")
    except PermissionError:
        sys.exit(f"{path} 를 읽을 수 없습니다 — 컨테이너는 root 가 아니라서 chmod 644 config.toml 이 필요합니다")
    except tomllib.TOMLDecodeError as e:
        sys.exit(f"설정 문법 오류 {path}: {e}")
    if os.environ.get("TOKEN"):
        cfg["token"] = os.environ["TOKEN"]
    if os.environ.get("BESZEL_PASSWORD"):
        cfg.setdefault("beszel", {})["password"] = os.environ["BESZEL_PASSWORD"]
    return cfg


# ---------- Beszel ----------

class Beszel:
    def __init__(self, cfg: Json) -> None:
        self.url = str(cfg.get("url", "")).rstrip("/")
        self.email = str(cfg.get("email", ""))
        self.password = str(cfg.get("password", ""))
        self.order: list[str] = [str(n) for n in cfg.get("order", [])]
        self._token: str | None = None
        self._auth_failed_at = 0.0
        self._lock = threading.Lock()

    @property
    def configured(self) -> bool:
        return bool(self.url and self.email and self.password)

    def _auth(self) -> str:
        # 한 번 모을 때 기기·알림이 같이 로그인하므로, 방금 실패했으면 다시 기다리지 않는다
        if time.monotonic() - self._auth_failed_at < AUTH_RETRY_SECONDS:
            raise RuntimeError("Beszel 로그인 직전에 실패 — 잠시 뒤 다시 시도")
        body = json.dumps({"identity": self.email, "password": self.password}).encode()
        try:
            return http_json(self.url + "/api/collections/users/auth-with-password", data=body)["token"]
        except HttpStatusError as e:
            self._auth_failed_at = time.monotonic()
            if e.code in (400, 401, 403):
                raise RuntimeError(f"Beszel 로그인 실패(HTTP {e.code}) — [beszel] email·password 확인") from e
            raise
        except Exception:
            self._auth_failed_at = time.monotonic()
            raise

    def get(self, path: str) -> Any:
        """토큰은 캐시하고, 401·403 이면 한 번 새로 받아 다시 부른다. 토큰 발급 실패는 다음 요청에서 다시 시도."""
        for attempt in range(2):
            with self._lock:
                if self._token is None:
                    self._token = self._auth()
                tok = self._token
            try:
                return http_json(self.url + path, {"Authorization": tok})
            except HttpStatusError as e:
                if e.code in (401, 403) and attempt == 0:
                    with self._lock:
                        if self._token == tok:
                            self._token = None
                    continue
                raise
        raise RuntimeError("unreachable")

    def systems(self) -> list[Json]:
        items = self.get(f"/api/collections/systems/records?perPage={BESZEL_PER_PAGE}")["items"]
        rank = {name: i for i, name in enumerate(self.order)}
        # sorted 는 안정 정렬이라 order 에 없는 기기는 원래 순서 그대로 뒤에 붙는다.
        items = sorted(items, key=lambda sy: rank.get(sy.get("name"), len(rank)))
        return [map_system(sy) for sy in items]

    def alert_names(self) -> list[str]:
        flt = urllib.parse.quote("triggered=true")
        items = self.get(f"/api/collections/alerts/records?filter={flt}&expand=system&perPage={BESZEL_PER_PAGE}")["items"]
        names = []
        for a in items:
            system = ((a.get("expand") or {}).get("system") or {}).get("name", "")
            names.append(f"{system} {a.get('name', '')}".strip())
        return names


def map_system(sy: Json) -> Json:
    i = sy.get("info") or {}
    efs = [v.get("dp", 0) if isinstance(v, dict) else v for v in (i.get("efs") or {}).values()]
    return {
        "name": sy.get("name", ""),
        "up": sy.get("status") == "up",
        "cpu": round(i.get("cpu", 0)),
        "mem": round(i.get("mp", 0)),
        "disk": round(max([i.get("dp", 0)] + efs)),
        "temp": round(i["dt"]) if i.get("dt") else None,
    }


# ---------- Prometheus ----------

class Prometheus:
    def __init__(self, cfg: Json) -> None:
        self.url = str(cfg.get("url", "")).rstrip("/")
        self.containers = bool(cfg.get("containers", False))

    @property
    def configured(self) -> bool:
        return bool(self.url)

    def query(self, q: str) -> list[Json]:
        res = http_json(self.url + "/api/v1/query?" + urllib.parse.urlencode({"query": q}))
        if res.get("status") != "success":
            raise RuntimeError(f"prometheus 오류: {res.get('error')}")
        return res["data"]["result"]

    def scalar(self, q: str) -> float | None:
        res = self.query(q)
        return float(res[0]["value"][1]) if res else None

    def alert_names(self) -> list[str]:
        return [r["metric"].get("alertname", "알림") for r in self.query(PROM_ALERTS_QUERY)]

    def top_containers(self) -> list[Json]:
        res = self.query(CONTAINERS_QUERY)
        res.sort(key=lambda r: -float(r["value"][1]))
        return [{"name": r["metric"].get("name", ""), "mem_mb": round(float(r["value"][1]) / BYTES_PER_MB)}
                for r in res]


# ---------- 서비스 ----------

def ms(seconds: float) -> str:
    return f"{seconds * 1000:.0f}ms"


def check_http(url: str, timeout: float, insecure: bool) -> Json:
    ctx = None
    if insecure:  # 사용자가 insecure=true 로 고른 경우만(자체 서명 인증서 등)
        ctx = ssl.create_default_context()
        ctx.check_hostname = False
        ctx.verify_mode = ssl.CERT_NONE
    req = urllib.request.Request(url, headers={"User-Agent": "nas-widget-server/1"})
    start = time.monotonic()
    try:
        with urllib.request.urlopen(req, timeout=timeout, context=ctx) as r:
            code = r.status
    except urllib.error.HTTPError as e:
        code = e.code
        e.close()
    if code >= 400:
        return {"ok": False}
    return {"ok": True, "value": ms(time.monotonic() - start)}


def check_tcp(target: str, timeout: float) -> Json:
    host, _, port = target.rpartition(":")
    start = time.monotonic()
    with socket.create_connection((host.strip("[]"), int(port)), timeout=timeout):
        pass
    return {"ok": True, "value": ms(time.monotonic() - start)}


def check_prometheus(prom: Prometheus, svc: Json) -> Json:
    if not prom.configured:
        raise RuntimeError("[prometheus] url 이 없습니다")
    if prom.scalar(str(svc["prometheus"])) != 1:
        return {"ok": False}
    out: Json = {"ok": True}
    if svc.get("prometheus_value"):
        v = prom.scalar(str(svc["prometheus_value"]))
        if v is not None:
            unit = str(svc.get("unit", ""))
            out["value"] = ms(v) if unit == "ms" else f"{v:g}{unit}"
    return out


def fetch_json(url: str, headers: dict[str, str], timeout: float) -> Any:
    """json 확인용 GET. 리다이렉트는 따라가지 않는다(headers 의 API 키가 다른 주소로 넘어가지 않게)."""
    req = urllib.request.Request(url, headers={"User-Agent": "nas-widget-server/1", "Accept": "application/json",
                                               **headers})
    try:
        with _SOURCE_OPENER.open(req, timeout=timeout) as r:
            data = r.read(JSON_MAX_BYTES + 1)
    except urllib.error.HTTPError as e:
        e.close()
        raise HttpStatusError(e.code) from e
    if len(data) > JSON_MAX_BYTES:
        raise ValueError("응답이 1MB 를 넘습니다")
    return json.loads(data)


def json_path(obj: Any, path: str) -> Any:
    """"data.items.0.count" 처럼 점으로 이은 경로를 따라 내려간다. 숫자 칸은 목록 번호."""
    for key in [k for k in path.split(".") if k]:
        if isinstance(obj, list):
            obj = obj[int(key)]
        elif isinstance(obj, dict):
            obj = obj[key]
        else:
            raise KeyError(key)
    return obj


def show_number(v: float) -> str:
    """1,234 · 12.5 · 0.0071 처럼. 지수 표기 없이, 너무 길면 유효 숫자 3자리로."""
    if v == int(v) and abs(v) < 1e15:
        text = f"{int(v):,}"
    else:
        text = f"{v:,.2f}" if abs(v) >= 1 else f"{v:.4f}"
        text = text.rstrip("0").rstrip(".")
    return text if len(text) <= 16 else f"{v:.3g}"


def show_value(v: Any, unit: str) -> str:
    if isinstance(v, bool):
        text = "예" if v else "아니오"
    elif isinstance(v, (int, float)):
        text = ms(v) if unit == "ms" else show_number(v) + unit
    elif v is None:
        text = "-"
    elif isinstance(v, (dict, list)):
        text = json.dumps(v, ensure_ascii=False, separators=(",", ":"))
    else:
        text = f"{v}{unit}"
    return text[:VALUE_MAX_CHARS]


def judge(svc: Json, v: Any) -> bool | None:
    """min·max 가 있으면 범위 안이면 True, 밖이면 False. 둘 다 없으면 None(판정 없는 값 줄)."""
    lo, hi = svc.get("min"), svc.get("max")
    if lo is None and hi is None:
        return None
    if isinstance(v, bool) or not isinstance(v, (int, float)):
        try:
            v = float(v)
        except (TypeError, ValueError):
            return False
    return (lo is None or v >= lo) and (hi is None or v <= hi)


def value_line(svc: Json, v: Any) -> Json:
    """값 줄: 판정이 없으면 info(회색), min·max 가 있으면 범위로 초록·빨강. 옛 위젯은 info 를 몰라 ok 로만 그린다."""
    ok = judge(svc, v)
    out: Json = {"ok": True if ok is None else ok, "value": show_value(v, str(svc.get("unit", "")))}
    if ok is None:
        out["info"] = True
    return out


def check_json(svc: Json, timeout: float) -> Json:
    headers = {str(k): str(v) for k, v in (svc.get("headers") or {}).items()}
    return value_line(svc, json_path(fetch_json(str(svc["json"]), headers, timeout), str(svc.get("path", ""))))


def check_prometheus_value(prom: Prometheus, svc: Json) -> Json:
    if not prom.configured:
        raise RuntimeError("[prometheus] url 이 없습니다")
    v = prom.scalar(str(svc["prometheus_value"]))
    if v is None:
        raise ValueError("쿼리 결과가 비었습니다")
    return value_line(svc, v)


SERVICE_KINDS = ("http", "tcp", "json", "prometheus", "prometheus_value")  # 앞의 것이 먼저(둘 이상 적으면)
VALUE_KINDS = ("json", "prometheus_value")


def service_kind(svc: Json) -> str | None:
    return next((k for k in SERVICE_KINDS if k in svc), None)


def validate_services(services: list[Json]) -> None:
    """설정 실수는 "못 읽음" 으로 숨기지 않고 뜰 때 알린다."""
    for svc in services:
        for key in ("min", "max"):
            v = svc.get(key)
            if v is not None and (isinstance(v, bool) or not isinstance(v, (int, float))):
                sys.exit(f"서비스 {svc.get('name', '?')} 의 {key} 는 따옴표 없는 숫자여야 합니다: {key} = {v!r}")


def check_service(svc: Json, prom: Prometheus) -> Json:
    name = str(svc.get("name", "?"))
    timeout = float(svc.get("timeout", DEFAULT_SERVICE_TIMEOUT))
    kind = service_kind(svc)
    try:
        if kind == "http":
            res = check_http(str(svc["http"]), timeout, bool(svc.get("insecure", False)))
        elif kind == "tcp":
            res = check_tcp(str(svc["tcp"]), timeout)
        elif kind == "json":
            res = check_json(svc, timeout)
        elif kind == "prometheus":
            res = check_prometheus(prom, svc)
        elif kind == "prometheus_value":
            res = check_prometheus_value(prom, svc)
        else:
            raise ValueError("http·tcp·json·prometheus·prometheus_value 중 하나가 필요합니다")
    except Exception as e:
        log.info("서비스 %s 실패: %r", name, e)
        res = {"ok": False}
        if kind in VALUE_KINDS:
            res["info"] = True  # 값 줄은 "죽음" 대신 "못 읽음" 으로 보인다
    return {"name": name, **res}


# ---------- 모으기 ----------

class Collector:
    def __init__(self, cfg: Json) -> None:
        self.cfg = cfg
        self.beszel = Beszel(cfg.get("beszel") or {})
        self.prom = Prometheus(cfg.get("prometheus") or {})
        self.services: list[Json] = list(cfg.get("services") or [])
        validate_services(self.services)
        self.cache_seconds = float(cfg.get("cache_seconds", DEFAULT_CACHE_SECONDS))
        self._cached: tuple[float, Json] | None = None
        self._lock = threading.Lock()

    def status(self) -> Json:
        with self._lock:  # 동시에 여러 요청이 와도 한 번만 모은다
            now = time.monotonic()
            if self._cached and now - self._cached[0] < self.cache_seconds:
                return self._cached[1]
            out = self.collect()
            self._cached = (time.monotonic(), out)
            return out

    def collect(self) -> Json:
        out: Json = {"time": int(time.time()), "systems": [], "services": [], "firing": None, "firing_names": []}

        with ThreadPoolExecutor(max_workers=SERVICE_WORKERS) as pool:
            futures = [pool.submit(check_service, s, self.prom) for s in self.services]

            # 소스도 병렬로 — 한 곳이 응답 없어도 위젯 제한 시간(20초) 안에 끝나게
            systems = pool.submit(self.beszel.systems) if self.beszel.configured else None
            sources = []
            if self.beszel.configured:
                sources.append(("Beszel", pool.submit(self.beszel.alert_names)))
            if self.prom.configured:
                sources.append(("Prometheus", pool.submit(self.prom.alert_names)))
            containers = pool.submit(self.prom.top_containers) if self.prom.configured and self.prom.containers else None

            if systems:
                try:
                    out["systems"] = systems.result()
                except Exception as e:
                    log.warning("Beszel 기기 실패: %s", e)

            names: list[str] = []
            succeeded = False
            for label, fut in sources:
                try:
                    names += fut.result()
                    succeeded = True
                except Exception as e:
                    log.warning("%s 알림 실패: %s", label, e)
            out["firing_names"] = names
            if succeeded:
                out["firing"] = len(names)

            if containers:
                try:
                    out["containers"] = containers.result()
                except Exception as e:
                    log.warning("컨테이너 메모리 실패: %s", e)
                    out["containers"] = []

            out["services"] = [f.result() for f in futures]
        return out


# ---------- HTTP ----------

def make_handler(collector: Collector, token: str, allow_query_token: bool = False) -> type[BaseHTTPRequestHandler]:
    class Handler(BaseHTTPRequestHandler):
        server_version = "nas-widget-server/1"
        sys_version = ""
        # 요청 줄을 안 보내고 붙잡고 있는 연결은 10초 뒤 끊는다
        timeout = REQUEST_TIMEOUT

        def setup(self) -> None:
            super().setup()
            # 소켓 timeout 은 읽기 한 번 기준이라, 1바이트씩 흘리면 끝없이 붙잡힌다 → 헤더까지 총 시간으로 끊는다
            self._deadline_passed = False
            self._header_timer = threading.Timer(HEADER_DEADLINE_SECONDS, self._header_deadline_passed)
            self._header_timer.daemon = True
            self._header_timer.start()

        def _header_deadline_passed(self) -> None:
            self._deadline_passed = True
            try:
                self.connection.shutdown(socket.SHUT_RDWR)
            except OSError:
                pass

        def parse_request(self) -> bool:
            ok = super().parse_request()  # 여기서 헤더까지 다 읽는다
            self._header_timer.cancel()
            if self._deadline_passed:
                # 끊기 전까지 받은 조각은 처리하지 않는다(응답도 보내지 않음)
                self.close_connection = True
                return False
            return ok

        def finish(self) -> None:
            self._header_timer.cancel()
            super().finish()

        def _send(self, code: int, body: bytes, ctype: str) -> None:
            self.send_response(code)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(body)))
            self.send_header("Cache-Control", "no-store")
            self.end_headers()
            self.wfile.write(body)

        def _authorized(self, query: dict[str, list[str]]) -> bool:
            if not token:
                return True
            header = self.headers.get("Authorization", "")
            if header.startswith("Bearer ") and hmac.compare_digest(header[7:].strip().encode(), token.encode()):
                return True
            if not allow_query_token:
                return False
            given = (query.get("token") or [""])[0]
            return bool(given) and hmac.compare_digest(given.encode(), token.encode())

        def do_GET(self) -> None:  # noqa: N802
            parsed = urllib.parse.urlsplit(self.path)
            if parsed.path == "/health":
                self._send(200, b"ok", "text/plain; charset=utf-8")
                return
            if parsed.path != "/status":
                self._send(404, b"not found", "text/plain; charset=utf-8")
                return
            if not self._authorized(urllib.parse.parse_qs(parsed.query)):
                log.warning("401 %s", self.address_string())
                self._send(401, b"unauthorized", "text/plain; charset=utf-8")
                return
            try:
                body = json.dumps(collector.status(), ensure_ascii=False).encode("utf-8")
            except Exception as e:
                log.exception("상태 만들기 실패: %r", e)
                self._send(500, b"internal error", "text/plain; charset=utf-8")
                return
            self._send(200, body, "application/json; charset=utf-8")

        def log_message(self, fmt: str, *args: Any) -> None:
            # ?token= 이 로그에 남지 않게 경로의 쿼리는 지운다.
            log.debug("%s %s", self.address_string(), (fmt % args).split("?")[0])

    return Handler


def max_connections_from_env() -> int:
    raw = os.environ.get("MAX_CONNECTIONS", "")
    try:
        n = int(raw) if raw else DEFAULT_MAX_CONNECTIONS
    except ValueError:
        log.warning("MAX_CONNECTIONS=%r 가 숫자가 아니라 기본 %d 을 씁니다", raw, DEFAULT_MAX_CONNECTIONS)
        return DEFAULT_MAX_CONNECTIONS
    return max(n, 1)


class Server(ThreadingHTTPServer):
    """동시 연결 수를 세마포어로 묶은 스레드 서버.

    server_bind 는 HTTPServer 의 socket.getfqdn 역방향 DNS 조회를 건너뛴다(DNS 가 느린 환경에서 기동이 수십 초 걸림).
    """

    def __init__(self, server_address: tuple[str, int], handler: type[BaseHTTPRequestHandler],
                 max_connections: int | None = None) -> None:
        self.max_connections = max_connections or max_connections_from_env()
        self._slots = threading.BoundedSemaphore(self.max_connections)
        super().__init__(server_address, handler)

    def process_request(self, request: Any, client_address: Any) -> None:
        if not self._slots.acquire(blocking=False):
            log.warning("동시 연결 %d개를 넘어 %s 연결을 닫습니다", self.max_connections, client_address[0])
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except BaseException:
            # 스레드를 못 띄웠으면 process_request_thread 가 안 돌므로 여기서 돌려준다
            self._slots.release()
            raise

    def process_request_thread(self, request: Any, client_address: Any) -> None:
        try:
            super().process_request_thread(request, client_address)
        finally:
            self._slots.release()

    def server_bind(self) -> None:
        socketserver.TCPServer.server_bind(self)
        host, port = self.server_address[:2]
        self.server_name = str(host)
        self.server_port = int(port)


def make_server(cfg: Json, host: str = "0.0.0.0", port: int = DEFAULT_PORT) -> Server:
    token = str(cfg.get("token", "") or "")
    if not token:
        log.warning("token 이 비어 있어 /status 를 누구나 읽을 수 있습니다 — 내부망 밖에 열지 마세요")
    collector = Collector(cfg)
    if not collector.beszel.configured and cfg.get("beszel"):
        log.warning("[beszel] url·email·password 중 빠진 값이 있어 기기 수치를 건너뜁니다")
    allow_query_token = cfg.get("allow_query_token") is True
    if allow_query_token:
        log.warning("allow_query_token = true — ?token= 은 프록시·브라우저 기록에 남을 수 있습니다")
    return Server((host, port), make_handler(collector, token, allow_query_token))


def main() -> None:
    logging.basicConfig(level=os.environ.get("LOG_LEVEL", "INFO"), stream=sys.stdout,
                        format="%(asctime)s %(levelname)s %(message)s")
    cfg = load_config()
    token = str(cfg.get("token", "") or "")
    allow_open = os.environ.get("ALLOW_NO_TOKEN") == "1" or cfg.get("allow_no_token") is True
    if not token and not allow_open:
        sys.exit("token 이 비어 있어요. config.toml 에 token 을 넣으세요(예: openssl rand -hex 24). "
                 "내부망에서 인증 없이 열려면 allow_no_token = true")
    if token and len(token) < 16:
        log.warning("token 이 16자보다 짧아요 — openssl rand -hex 24 같은 긴 값을 권합니다")
    port = int(os.environ.get("PORT", DEFAULT_PORT))
    server = make_server(cfg, "0.0.0.0", port)
    log.info("http://0.0.0.0:%d/status 에서 듣는 중", port)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()


if __name__ == "__main__":
    main()
