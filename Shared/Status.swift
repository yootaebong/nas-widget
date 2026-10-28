import Foundation
import SwiftUI

struct NasStatus: Codable {
    struct System: Codable, Identifiable {
        var name: String
        var up: Bool
        var cpu: Int
        var mem: Int
        var disk: Int
        var temp: Int?
        var id: String { name }
    }
    struct Service: Codable, Identifiable {
        var name: String
        var ok: Bool
        var value: String?
        /// 판정 없는 값 줄(회색). 서버 v1.7 부터
        var info: Bool?
        var id: String { name }
    }
    struct Container: Codable, Identifiable {
        var name: String
        var mem_mb: Int
        var id: String { name }
    }
    var time: Int
    var systems: [System]
    var services: [Service]
    var firing: Int?
    var firing_names: [String]?
    var relay_connections: Int?
    var containers: [Container]?

    static let sample = NasStatus(
        time: Int(Date().timeIntervalSince1970),
        systems: [.init(name: "중앙 서버", up: true, cpu: 12, mem: 37, disk: 84, temp: 52),
                  .init(name: "맥북", up: true, cpu: 45, mem: 75, disk: 74, temp: 61),
                  .init(name: "데스크톱", up: true, cpu: 64, mem: 57, disk: 52, temp: nil)],
        services: [.init(name: "웹", ok: true, value: "56ms"), .init(name: "Redis", ok: true, value: nil), .init(name: "방문자", ok: true, value: "120", info: true),
                   .init(name: "DB", ok: true, value: nil), .init(name: "인터넷", ok: true, value: "7ms")],
        firing: 1, firing_names: ["웹 응답 느림"], relay_connections: 14,
        containers: [.init(name: "postgres", mem_mb: 1830), .init(name: "redis", mem_mb: 389),
                     .init(name: "grafana", mem_mb: 301)])
}

/// 빌드 때 `Local.xcconfig` 로 넣은 값. 배포판은 비어 있고, 위젯 편집·앱 창에서 넣은 값이 우선한다.
func infoValue(_ key: String) -> String? {
    (Bundle.main.object(forInfoDictionaryKey: key) as? String).flatMap { $0.isEmpty ? nil : $0 }
}

/// http·https 주소만 받는다. 비었거나 잘못되면 nil.
func webURL(_ text: String?) -> URL? {
    guard let t = text?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty,
          let u = URL(string: t), let scheme = u.scheme?.lowercased(),
          scheme == "http" || scheme == "https", u.host != nil else { return nil }
    return u
}

/// IP 글자면 그 바이트(IPv4 4개·IPv6 16개), 아니면 nil. inet_pton 은 10진 점 4개만 IPv4 로 받는다.
func ipBytes(_ host: String) -> [UInt8]? {
    var v4 = in_addr()
    if inet_pton(AF_INET, host, &v4) == 1 { return withUnsafeBytes(of: &v4) { Array($0) } }
    var v6 = in6_addr()
    if inet_pton(AF_INET6, host, &v6) == 1 { return withUnsafeBytes(of: &v6) { Array($0) } }
    return nil
}

/// 이 맥의 네트워크 장치에 100.64/10 주소가 있나 — Tailscale 이 켜져 있다는 뜻.
/// 없으면 100.x 는 통신사 CGNAT 망일 수 있어 내부로 치지 않는다.
func hasCGNATInterface() -> Bool {
    var list: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&list) == 0 else { return false }
    defer { freeifaddrs(list) }
    var p = list
    while let ifa = p {
        if let sa = ifa.pointee.ifa_addr, sa.pointee.sa_family == UInt8(AF_INET) {
            let a = sa.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            let b = withUnsafeBytes(of: a) { Array($0) }
            if b[0] == 100 && (64...127).contains(b[1]) { return true }
        }
        p = ifa.pointee.ifa_next
    }
    return false
}

/// 밖으로 안 나가는 IP 인지: 사설·루프백·링크 로컬, Tailscale(100.64/10, 켜져 있을 때만), IPv6 ::1·fc00::/7·fe80::/10
func isLocalIP(_ b: [UInt8]) -> Bool {
    if b.count == 4 {
        return b[0] == 10 || b[0] == 127
            || (b[0] == 172 && (16...31).contains(b[1]))
            || (b[0] == 192 && b[1] == 168)
            || (b[0] == 169 && b[1] == 254)
            || (b[0] == 100 && (64...127).contains(b[1]) && hasCGNATInterface())
    }
    if b.count == 16 {
        return b == [UInt8](repeating: 0, count: 15) + [1]
            || b[0] & 0xfe == 0xfc
            || (b[0] == 0xfe && b[1] & 0xc0 == 0x80)
    }
    return false
}

func normalizedHost(_ host: String?) -> String? {
    guard var h = host?.lowercased(), !h.isEmpty else { return nil }
    if h.hasPrefix("[") { h = String(h.dropFirst().dropLast()) }
    if h.hasSuffix(".") { h = String(h.dropLast()) }
    return h
}

/// 집 안·Tailscale 처럼 밖으로 안 나가는 주소인지. 이런 곳만 http(암호화 없음)로 읽는다.
/// ATS 는 모두 허용(NSAllowsArbitraryLoads)이라 http 를 막는 곳은 여기와 `checkResolvesLocal` 뿐이다.
/// (NSAllowsLocalNetworking 은 Tailscale 100.x 를 내부망으로 안 쳐 -1022 로 막는다 — 2026-10-28 실측)
func isLocalHost(_ host: String?) -> Bool {
    guard let h = normalizedHost(host) else { return false }
    if let b = ipBytes(h) { return isLocalIP(b) }
    // 16843009·0x01010101 처럼 정수 하나로 쓴 IP 는 공개 주소일 수 있다
    if h.hasPrefix("0x") || h.allSatisfy(\.isNumber) || h.contains(":") { return false }
    // 이름은 점 없는 이름(MagicDNS 등)·.local 만 — 실제로 어디로 풀리는지는 보내기 전에 다시 본다
    return h == "localhost" || !h.contains(".") || h.hasSuffix(".local")
}

/// 이름으로 넣은 http 주소가 정말 내부 IP 로만 풀리는지. 공용 와이파이 DNS 가 `nas` 를 바깥 IP 로 답하면 막는다.
func checkResolvesLocal(_ host: String) throws {
    var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                         ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
    var res: UnsafeMutablePointer<addrinfo>?
    guard getaddrinfo(host, nil, &hints, &res) == 0, let first = res else { throw URLError(.cannotFindHost) }
    defer { freeaddrinfo(first) }
    var p: UnsafeMutablePointer<addrinfo>? = first
    while let ai = p {
        var b: [UInt8] = []
        if ai.pointee.ai_family == AF_INET {
            let a = ai.pointee.ai_addr.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee.sin_addr }
            b = withUnsafeBytes(of: a) { Array($0) }
        } else if ai.pointee.ai_family == AF_INET6 {
            let a = ai.pointee.ai_addr.withMemoryRebound(to: sockaddr_in6.self, capacity: 1) { $0.pointee.sin6_addr }
            b = withUnsafeBytes(of: a) { Array($0) }
        }
        if !isLocalIP(b) { throw StatusError.insecurePublic }
        p = ai.pointee.ai_next
    }
}

/// 공개 주소에 http 로 토큰·상태를 보내지 않는다 — 가는 길에 누구나 읽을 수 있다.
func isPlainHTTPToPublic(_ url: URL) -> Bool {
    url.scheme?.lowercased() == "http" && !isLocalHost(url.host)
}

func nonEmpty(_ text: String?) -> String? {
    text.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.flatMap { $0.isEmpty ? nil : $0 }
}

/// 상태를 어디서 읽을지. 넣은 값이 비면 빌드 때 값으로 돌아간다.
struct StatusSource {
    var url: URL?
    var token: String?
    var dashboard: URL?
    /// 주소를 넣었는데 http·https 주소가 아님
    var badURL = false

    init(url: String?, token: String?, dashboard: String?) {
        if let typed = nonEmpty(url) {
            self.url = webURL(typed)
            badURL = self.url == nil
            self.token = nonEmpty(token)
        } else {
            // 빌드 때 토큰은 빌드 때 주소에만 보낸다 — 다른 서버로 새지 않게
            self.url = webURL(infoValue("NASStatusURL"))
            self.token = nonEmpty(token) ?? infoValue("NASStatusToken")
        }
        self.dashboard = webURL(nonEmpty(dashboard) ?? infoValue("DashboardURL"))
    }
}

func memText(_ mb: Int) -> String {
    mb >= 1024 ? String(format: "%.1fGB", Double(mb) / 1024) : "\(mb)MB"
}

enum StatusError: LocalizedError {
    case noURL, badURL, insecurePublic, tooLarge, unauthorized, http(Int)
    var errorDescription: String? {
        switch self {
        case .noURL: "상태 주소가 없어요"
        case .badURL: "주소는 http:// 또는 https:// 로 시작해야 해요"
        case .insecurePublic: "공개 주소는 https:// 로 넣어 주세요 (http 는 집 안·Tailscale 주소만)"
        case .tooLarge: "서버 응답이 너무 커요"
        case .unauthorized: "토큰이 맞지 않아요"
        case .http(let code): "서버 응답 \(code)"
        }
    }
}

/// 리다이렉트를 따라가지 않는다 — https 에서 http 로 내려가며 토큰이 새지 않게
final class NoRedirect: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? { nil }
}

enum StatusClient {
    static let maxBytes = 512_000

    static func fetch(_ source: StatusSource) async throws -> NasStatus {
        if source.badURL { throw StatusError.badURL }
        guard let url = source.url else { throw StatusError.noURL }
        if isPlainHTTPToPublic(url) { throw StatusError.insecurePublic }
        if url.scheme?.lowercased() == "http", let h = normalizedHost(url.host), ipBytes(h) == nil {
            try checkResolvesLocal(h)
        }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        if let token = source.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        // 위젯 확장은 메모리가 작다 — 본문은 maxBytes 까지만 받는다
        let (bytes, resp) = try await URLSession.shared.bytes(for: req, delegate: NoRedirect())
        if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 400 {
            throw code == 401 ? StatusError.unauthorized : StatusError.http(code)
        }
        if resp.expectedContentLength > maxBytes { throw StatusError.tooLarge }
        var data = Data()
        for try await b in bytes {
            data.append(b)
            if data.count > maxBytes { throw StatusError.tooLarge }
        }
        var s = try JSONDecoder().decode(NasStatus.self, from: data)
        // 위젯 한 칸에 다 못 그리는 만큼은 버린다
        s.systems = Array(s.systems.prefix(12))
        s.services = Array(s.services.prefix(16))
        s.containers = s.containers.map { Array($0.prefix(5)) }
        s.firing_names = s.firing_names.map { Array($0.prefix(20)) }
        return s
    }
}

func levelColor(_ v: Int) -> Color {
    v >= 90 ? .red : v >= 70 ? .orange : .green
}

func tempColor(_ v: Int) -> Color {
    v >= 90 ? .red : v >= 75 ? .orange : .green
}
