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

/// 집 안·Tailscale 처럼 밖으로 안 나가는 주소인지. 이런 곳만 http(암호화 없음)로 읽는다.
func isLocalHost(_ host: String?) -> Bool {
    guard var h = host?.lowercased(), !h.isEmpty else { return false }
    if h.hasPrefix("[") { h = String(h.dropFirst().dropLast()) }
    if h.hasSuffix(".") { h = String(h.dropLast()) }
    // 16843009·0x01010101 처럼 정수 하나로 쓴 IP 는 공개 주소일 수 있다
    if h.hasPrefix("0x") || h.allSatisfy(\.isNumber) { return false }
    // ATS(NSAllowsLocalNetworking)가 http 를 허락하는 이름과 맞춘다: 점 없는 이름·.local·IP
    if h == "localhost" || !h.contains(".") && !h.contains(":") || h.hasSuffix(".local") { return true }
    let p = h.split(separator: ".").compactMap { $0.allSatisfy(\.isNumber) ? UInt8($0) : nil }
    if p.count == 4 && h.split(separator: ".").count == 4 {
        return p[0] == 10 || p[0] == 127
            || (p[0] == 172 && (16...31).contains(p[1]))
            || (p[0] == 192 && p[1] == 168)
            || (p[0] == 169 && p[1] == 254)
            || (p[0] == 100 && (64...127).contains(p[1]))  // Tailscale
    }
    if h.contains(":") {  // IPv6: 루프백·사설(fc00::/7)·링크 로컬(fe80::/10)
        return h == "::1" || h.hasPrefix("fc") || h.hasPrefix("fd") || h.hasPrefix("fe8") || h.hasPrefix("fe9")
            || h.hasPrefix("fea") || h.hasPrefix("feb")
    }
    return false
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
    v >= 90 ? .red : v >= 70 ? .yellow : .green
}

func tempColor(_ v: Int) -> Color {
    v >= 90 ? .red : v >= 75 ? .yellow : .green
}
