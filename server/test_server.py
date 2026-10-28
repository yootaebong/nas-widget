"""nas_widget_server 통합 시험. 가짜 Beszel(PocketBase)·Prometheus·웹 서버를 띄워 실제 서버로 확인한다."""

from __future__ import annotations

import json
import logging
import os
import socket
import threading
import time
import unittest
import urllib.error
import urllib.parse
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any
from unittest import mock

import nas_widget_server as srv

logging.getLogger("nas-widget-server").setLevel(logging.CRITICAL)  # 실패 시험의 경고 로그는 숨긴다

TOKEN = "secret-token"
BESZEL_EMAIL = "a@b.c"
BESZEL_PASSWORD = "pw"

SYSTEMS = [
    {"name": "맥북", "status": "up", "info": {"cpu": 45.4, "mp": 74.6, "dp": 50, "efs": {"ext": {"dp": 73.6}}}},
    {"name": "데스크톱", "status": "down", "info": {"cpu": 1, "mp": 2, "dp": 3, "efs": {"old": 88.2}, "dt": 0}},
    {"name": "NAS", "status": "up", "info": {"cpu": 12.2, "mp": 37, "dp": 84.4, "dt": 51.6}},
]
BESZEL_ALERTS = [{"name": "CPU", "expand": {"system": {"name": "NAS"}}}]


class FakeServer:
    """핸들러 함수(path, headers, body) -> (code, obj[, 응답 헤더]) 를 받아 스레드로 띄우는 작은 서버."""

    def __init__(self, route) -> None:
        self.route = route
        self.calls: list[str] = []
        fake = self

        class H(BaseHTTPRequestHandler):
            def _do(self, body: bytes | None) -> None:
                fake.calls.append(self.path)
                code, obj, *extra = fake.route(self.path, self.headers, body)
                data = obj if isinstance(obj, bytes) else json.dumps(obj).encode()
                self.send_response(code)
                for k, v in (extra[0] if extra else {}).items():
                    self.send_header(k, v)
                self.send_header("Content-Length", str(len(data)))
                self.end_headers()
                self.wfile.write(data)

            def do_GET(self) -> None:  # noqa: N802
                self._do(None)

            def do_POST(self) -> None:  # noqa: N802
                self._do(self.rfile.read(int(self.headers.get("Content-Length", 0))))

            def log_message(self, *a: Any) -> None:
                pass

        self.httpd = srv.Server(("127.0.0.1", 0), H)
        self.url = f"http://127.0.0.1:{self.httpd.server_address[1]}"
        threading.Thread(target=self.httpd.serve_forever, daemon=True).start()

    def close(self) -> None:
        self.httpd.shutdown()
        self.httpd.server_close()


def beszel_route(state: dict[str, Any]):
    def route(path: str, headers, body):
        if path == "/api/collections/users/auth-with-password":
            cred = json.loads(body)
            if cred == {"identity": BESZEL_EMAIL, "password": BESZEL_PASSWORD}:
                state["issued"] += 1
                return 200, {"token": f"tok{state['issued']}"}
            return 400, {"message": "bad"}
        if headers.get("Authorization") != state["valid"]():
            return 401, {"message": "unauthorized"}
        if path.startswith("/api/collections/systems/records"):
            return 200, {"items": SYSTEMS}
        if path.startswith("/api/collections/alerts/records"):
            q = urllib.parse.parse_qs(urllib.parse.urlsplit(path).query)
            assert q["filter"] == ["triggered=true"] and q["expand"] == ["system"], q
            return 200, {"items": BESZEL_ALERTS}
        return 404, {}

    return route


def prom_route(path: str, headers, body):
    q = urllib.parse.parse_qs(urllib.parse.urlsplit(path).query).get("query", [""])[0]
    vec = lambda rows: (200, {"status": "success", "data": {"resultType": "vector", "result": rows}})  # noqa: E731
    if q == srv.PROM_ALERTS_QUERY:
        return vec([{"metric": {"alertname": "DB 다운"}, "value": [0, "1"]}])
    if q == srv.CONTAINERS_QUERY:
        return vec([{"metric": {"name": "grafana"}, "value": [0, str(301 * 1048576)]},
                    {"metric": {"name": "postgres"}, "value": [0, str(1830 * 1048576)]}])
    if q == "up_ok":
        return vec([{"metric": {}, "value": [0, "1"]}])
    if q == "rtt":
        return vec([{"metric": {}, "value": [0, "0.0071"]}])
    if q == "up_bad":
        return vec([{"metric": {}, "value": [0, "0"]}])
    return vec([])


def web_route(path: str, headers, body):
    return (200, b"hi") if path == "/ok" else (503, b"down")


def closed_port() -> int:
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


class ServerTest(unittest.TestCase):
    def setUp(self) -> None:
        self.fakes: list[FakeServer] = []
        self.servers: list[ThreadingHTTPServer] = []

    def tearDown(self) -> None:
        for s in self.servers:
            s.shutdown()
            s.server_close()
        for f in self.fakes:
            f.close()

    def fake(self, route) -> FakeServer:
        f = FakeServer(route)
        self.fakes.append(f)
        return f

    def start(self, cfg: dict[str, Any], env: dict[str, str] | None = None) -> str:
        cfg.setdefault("cache_seconds", 0)
        with mock.patch.dict(os.environ, env or {}):
            s = srv.make_server(cfg, "127.0.0.1", 0)
        threading.Thread(target=s.serve_forever, daemon=True).start()
        self.servers.append(s)
        return f"http://127.0.0.1:{s.server_address[1]}"

    def get(self, url: str, headers: dict[str, str] | None = None) -> tuple[int, Any]:
        req = urllib.request.Request(url, headers=headers or {})
        try:
            with urllib.request.urlopen(req, timeout=10) as r:
                raw = r.read()
                return r.status, json.loads(raw) if "json" in r.headers.get("Content-Type", "") else raw.decode()
        except urllib.error.HTTPError as e:
            with e:
                return e.code, e.read().decode()

    def beszel(self, state: dict[str, Any] | None = None) -> tuple[FakeServer, dict[str, Any]]:
        st = state or {"issued": 0}
        st.setdefault("valid", lambda: f"tok{st['issued']}")
        return self.fake(beszel_route(st)), st

    def beszel_cfg(self, url: str, **extra: Any) -> dict[str, Any]:
        return {"url": url, "email": BESZEL_EMAIL, "password": BESZEL_PASSWORD, **extra}

    # (a) 인증
    def test_auth(self) -> None:
        base = self.start({"token": TOKEN})
        self.assertEqual(self.get(base + "/status")[0], 401)
        self.assertEqual(self.get(base + "/status", {"Authorization": "Bearer nope"})[0], 401)
        self.assertEqual(self.get(base + "/status", {"Authorization": f"Bearer {TOKEN}"})[0], 200)
        self.assertEqual(self.get(base + f"/status?token={TOKEN}")[0], 401)  # 쿼리 토큰은 기본 거부
        self.assertEqual(self.get(base + "/health"), (200, "ok"))

    def test_query_token_opt_in(self) -> None:
        base = self.start({"token": TOKEN, "allow_query_token": True})
        self.assertEqual(self.get(base + "/status?token=nope")[0], 401)
        self.assertEqual(self.get(base + f"/status?token={TOKEN}")[0], 200)
        self.assertEqual(self.get(base + "/status", {"Authorization": f"Bearer {TOKEN}"})[0], 200)

    # 연결 보호
    def test_connection_limit(self) -> None:
        base = self.start({}, env={"MAX_CONNECTIONS": "2"})
        port = int(base.rsplit(":", 1)[1])
        idle = [socket.create_connection(("127.0.0.1", port), timeout=5) for _ in range(2)]
        try:
            time.sleep(0.2)  # 두 연결이 슬롯을 잡을 때까지
            with socket.create_connection(("127.0.0.1", port), timeout=5) as third:
                start = time.monotonic()
                try:
                    data = third.recv(1)
                except ConnectionResetError:
                    data = b""
                self.assertEqual(data, b"")  # 요청도 받기 전에 닫힘
                self.assertLess(time.monotonic() - start, 2)
        finally:
            for s in idle:
                s.close()
        deadline = time.monotonic() + 5
        while True:
            try:
                self.assertEqual(self.get(base + "/status")[0], 200)
                break
            except (urllib.error.URLError, ConnectionError):
                if time.monotonic() > deadline:
                    raise
                time.sleep(0.1)

    def test_header_deadline(self) -> None:
        old, srv.HEADER_DEADLINE_SECONDS = srv.HEADER_DEADLINE_SECONDS, 0.5
        self.addCleanup(setattr, srv, "HEADER_DEADLINE_SECONDS", old)
        base = self.start({})
        port = int(base.rsplit(":", 1)[1])
        with socket.create_connection(("127.0.0.1", port), timeout=5) as s:
            start = time.monotonic()
            closed = False
            for ch in b"GET /status HTTP/1.1\r\nX-Slow: " + b"a" * 100:
                try:
                    s.sendall(bytes([ch]))
                except OSError:
                    closed = True
                    break
                s.settimeout(0.1)
                try:
                    if s.recv(1) == b"":
                        closed = True
                        break
                except TimeoutError:
                    pass
                except OSError:
                    closed = True
                    break
            self.assertTrue(closed)
            self.assertLess(time.monotonic() - start, 3)

    def test_source_redirect_not_followed(self) -> None:
        target = self.fake(prom_route)
        redirect = lambda path, headers, body: (302, b"", {"Location": target.url + path})  # noqa: E731
        bz = self.fake(redirect)
        prom = self.fake(redirect)
        base = self.start({"beszel": self.beszel_cfg(bz.url), "prometheus": {"url": prom.url}})
        code, body = self.get(base + "/status")
        self.assertEqual(code, 200)
        self.assertIsNone(body["firing"])
        self.assertEqual(body["systems"], [])
        self.assertEqual(target.calls, [])  # 비밀번호·토큰이 다른 주소로 가지 않음

    def test_no_token_is_open(self) -> None:
        base = self.start({})
        code, body = self.get(base + "/status")
        self.assertEqual(code, 200)
        self.assertEqual(body["systems"], [])
        self.assertEqual(body["services"], [])
        self.assertIsNone(body["firing"])
        self.assertEqual(body["firing_names"], [])
        self.assertNotIn("containers", body)
        self.assertNotIn("relay_connections", body)

    def test_env_overrides(self) -> None:
        path = os.path.join(os.path.dirname(__file__), ".test_config.toml")
        with open(path, "w", encoding="utf-8") as f:
            f.write('token = "file"\n[beszel]\nurl = "http://x"\npassword = "file"\n')
        old = {k: os.environ.get(k) for k in ("CONFIG", "TOKEN", "BESZEL_PASSWORD")}
        try:
            os.environ.update(CONFIG=path, TOKEN="env-t", BESZEL_PASSWORD="env-p")
            cfg = srv.load_config()
        finally:
            os.remove(path)
            for k, v in old.items():
                if v is None:
                    os.environ.pop(k, None)
                else:
                    os.environ[k] = v
        self.assertEqual(cfg["token"], "env-t")
        self.assertEqual(cfg["beszel"]["password"], "env-p")

    # (b) 기기 매핑·순서·알림
    def test_systems_and_alerts(self) -> None:
        bz, _ = self.beszel()
        prom = self.fake(prom_route)
        base = self.start({"beszel": self.beszel_cfg(bz.url, order=["NAS", "없는기기"]),
                           "prometheus": {"url": prom.url}})
        code, body = self.get(base + "/status")
        self.assertEqual(code, 200)
        self.assertEqual(body["systems"], [
            {"name": "NAS", "up": True, "cpu": 12, "mem": 37, "disk": 84, "temp": 52},
            {"name": "맥북", "up": True, "cpu": 45, "mem": 75, "disk": 74, "temp": None},
            {"name": "데스크톱", "up": False, "cpu": 1, "mem": 2, "disk": 88, "temp": None},
        ])
        self.assertEqual(body["firing"], 2)
        self.assertEqual(body["firing_names"], ["NAS CPU", "DB 다운"])
        self.assertNotIn("containers", body)  # containers=true 가 아니면 생략

    def test_beszel_token_cached_and_renewed(self) -> None:
        bz, st = self.beszel()
        base = self.start({"beszel": self.beszel_cfg(bz.url)})
        self.get(base + "/status")
        self.get(base + "/status")
        self.assertEqual(st["issued"], 1)  # 캐시
        st["valid"] = lambda: "rotated" if st["issued"] < 2 else "tok2"
        code, body = self.get(base + "/status")
        self.assertEqual(code, 200)
        self.assertEqual(st["issued"], 2)  # 401 뒤 재발급
        self.assertEqual(len(body["systems"]), 3)

    def test_utf8_raw(self) -> None:
        bz, _ = self.beszel()
        base = self.start({"beszel": self.beszel_cfg(bz.url)})
        with urllib.request.urlopen(base + "/status", timeout=10) as r:
            self.assertIn("charset=utf-8", r.headers["Content-Type"])
            self.assertIn("맥북".encode(), r.read())

    # (c) 서비스
    def test_services(self) -> None:
        web = self.fake(web_route)
        prom = self.fake(prom_route)
        base = self.start({"prometheus": {"url": prom.url}, "services": [
            {"name": "웹", "http": web.url + "/ok"},
            {"name": "죽은웹", "http": web.url + "/bad"},
            {"name": "닫힌포트", "tcp": f"127.0.0.1:{closed_port()}", "timeout": 1},
            {"name": "열린포트", "tcp": web.url.removeprefix("http://")},
            {"name": "인터넷", "prometheus": "up_ok", "prometheus_value": "rtt", "unit": "ms"},
            {"name": "Redis", "prometheus": "up_bad"},
            {"name": "잘못", "foo": "bar"},
        ]})
        svcs = {s["name"]: s for s in self.get(base + "/status")[1]["services"]}
        self.assertEqual(list(svcs), ["웹", "죽은웹", "닫힌포트", "열린포트", "인터넷", "Redis", "잘못"])
        self.assertTrue(svcs["웹"]["ok"])
        self.assertRegex(svcs["웹"]["value"], r"^\d+ms$")
        self.assertEqual(svcs["죽은웹"], {"name": "죽은웹", "ok": False})
        self.assertEqual(svcs["닫힌포트"], {"name": "닫힌포트", "ok": False})
        self.assertTrue(svcs["열린포트"]["ok"])
        self.assertEqual(svcs["인터넷"], {"name": "인터넷", "ok": True, "value": "7ms"})
        self.assertEqual(svcs["Redis"], {"name": "Redis", "ok": False})
        self.assertFalse(svcs["잘못"]["ok"])

    def test_value_lines(self) -> None:
        def api(path: str, headers, body):
            if path == "/stats":
                if headers.get("X-Api-Key") != "k":
                    return 401, {}
                return 200, {"data": {"visitors": 1234, "items": [{"last": "03:00"}], "on": True}}
            if path == "/big":
                return 200, b"[" + b"0," * srv.JSON_MAX_BYTES + b"0]"
            if path == "/moved":
                return 302, b"", {"Location": "/stats"}
            return 404, {}

        web = self.fake(api)
        prom = self.fake(prom_route)
        key = {"X-Api-Key": "k"}
        base = self.start({"prometheus": {"url": prom.url}, "services": [
            {"name": "방문자", "json": web.url + "/stats", "path": "data.visitors", "headers": key, "unit": "명"},
            {"name": "백업", "json": web.url + "/stats", "path": "data.items.0.last", "headers": key},
            {"name": "켜짐", "json": web.url + "/stats", "path": "data.on", "headers": key},
            {"name": "많음", "json": web.url + "/stats", "path": "data.visitors", "headers": key, "max": 1000},
            {"name": "충분", "json": web.url + "/stats", "path": "data.visitors", "headers": key, "min": 100},
            {"name": "키없음", "json": web.url + "/stats", "path": "data.visitors"},
            {"name": "없는칸", "json": web.url + "/stats", "path": "data.nope", "headers": key},
            {"name": "큼", "json": web.url + "/big"},
            {"name": "이동", "json": web.url + "/moved", "headers": key},
            {"name": "지연", "prometheus_value": "rtt", "unit": "ms"},
            {"name": "빈쿼리", "prometheus_value": "nothing"},
        ]})
        svcs = {s.pop("name"): s for s in self.get(base + "/status")[1]["services"]}
        self.assertEqual(svcs["방문자"], {"ok": True, "value": "1,234명", "info": True})
        self.assertEqual(svcs["백업"], {"ok": True, "value": "03:00", "info": True})
        self.assertEqual(svcs["켜짐"], {"ok": True, "value": "예", "info": True})
        self.assertEqual(svcs["많음"], {"ok": False, "value": "1,234"})
        self.assertEqual(svcs["충분"], {"ok": True, "value": "1,234"})
        for name in ["키없음", "없는칸", "큼", "이동", "빈쿼리"]:
            self.assertEqual(svcs[name], {"ok": False, "info": True}, name)
        self.assertEqual(svcs["지연"], {"ok": True, "value": "7ms", "info": True})
        self.assertEqual(web.calls.count("/stats"), 7)  # "이동" 의 302 를 따라가지 않음

    def test_show_value(self) -> None:
        self.assertEqual(srv.show_value(0.5, ""), "0.5")
        self.assertEqual(srv.show_value(12345678, ""), "12,345,678")
        self.assertEqual(srv.show_value(999999.9, ""), "999,999.9")
        self.assertEqual(srv.show_value(1e-7, ""), "0")
        self.assertEqual(srv.show_value(12.5, "%"), "12.5%")
        self.assertEqual(srv.show_value(1e22, ""), "1e+22")
        self.assertEqual(srv.show_value({"a": 1}, ""), '{"a":1}')
        with self.assertRaises(SystemExit):
            srv.validate_services([{"name": "x", "json": "u", "min": "1"}])
        self.assertEqual(srv.service_kind({"http": "u", "json": "v"}), "http")
        self.assertEqual(srv.show_value(None, ""), "-")
        self.assertEqual(len(srv.show_value("가" * 100, "")), srv.VALUE_MAX_CHARS)
        self.assertFalse(srv.judge({"max": 10}, "abc"))
        self.assertTrue(srv.judge({"max": 10}, "5"))

    # (d) Beszel 다운
    def test_beszel_down(self) -> None:
        base = self.start({"beszel": self.beszel_cfg(f"http://127.0.0.1:{closed_port()}"),
                           "services": [{"name": "x", "tcp": f"127.0.0.1:{closed_port()}", "timeout": 1}]})
        code, body = self.get(base + "/status")
        self.assertEqual(code, 200)
        self.assertEqual(body["systems"], [])
        self.assertIsNone(body["firing"])
        self.assertEqual(body["firing_names"], [])
        self.assertEqual(body["services"], [{"name": "x", "ok": False}])

    def test_beszel_bad_login_retried(self) -> None:
        bz, st = self.beszel()
        cfg = self.beszel_cfg(bz.url, password="wrong")
        base = self.start({"beszel": cfg})
        self.assertEqual(self.get(base + "/status")[1]["systems"], [])
        logins = sum(p.endswith("auth-with-password") for p in bz.calls)
        self.assertEqual(logins, 1)  # 같은 수집 안의 알림 조회는 다시 로그인하지 않는다
        old, srv.AUTH_RETRY_SECONDS = srv.AUTH_RETRY_SECONDS, 0.0
        self.addCleanup(setattr, srv, "AUTH_RETRY_SECONDS", old)
        self.get(base + "/status")
        self.assertGreater(sum(p.endswith("auth-with-password") for p in bz.calls), logins)  # 다음 요청에 다시 시도

    def test_one_alert_source_ok(self) -> None:
        prom = self.fake(prom_route)
        base = self.start({"beszel": self.beszel_cfg(f"http://127.0.0.1:{closed_port()}"),
                           "prometheus": {"url": prom.url}})
        body = self.get(base + "/status")[1]
        self.assertEqual(body["firing"], 1)
        self.assertEqual(body["firing_names"], ["DB 다운"])

    # (e) 컨테이너
    def test_containers(self) -> None:
        prom = self.fake(prom_route)
        base = self.start({"prometheus": {"url": prom.url, "containers": True}})
        body = self.get(base + "/status")[1]
        self.assertEqual(body["containers"], [{"name": "postgres", "mem_mb": 1830}, {"name": "grafana", "mem_mb": 301}])

    def test_containers_prom_down(self) -> None:
        base = self.start({"prometheus": {"url": f"http://127.0.0.1:{closed_port()}", "containers": True}})
        code, body = self.get(base + "/status")
        self.assertEqual(code, 200)
        self.assertEqual(body["containers"], [])
        self.assertIsNone(body["firing"])

    def test_cache(self) -> None:
        bz, _ = self.beszel()
        base = self.start({"beszel": self.beszel_cfg(bz.url), "cache_seconds": 60})
        first = self.get(base + "/status")[1]
        n = len(bz.calls)
        self.assertEqual(self.get(base + "/status")[1], first)
        self.assertEqual(len(bz.calls), n)


if __name__ == "__main__":
    unittest.main()
