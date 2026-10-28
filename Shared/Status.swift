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
        systems: [.init(name: "NAS", up: true, cpu: 12, mem: 37, disk: 84, temp: 52),
                  .init(name: "맥북", up: true, cpu: 45, mem: 75, disk: 74, temp: 61),
                  .init(name: "데스크톱", up: true, cpu: 64, mem: 57, disk: 52, temp: nil)],
        services: [.init(name: "웹", ok: true, value: "56ms"), .init(name: "Redis", ok: true, value: nil),
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
    case noURL, badURL, unauthorized, http(Int)
    var errorDescription: String? {
        switch self {
        case .noURL: "상태 주소가 없어요"
        case .badURL: "주소는 http:// 또는 https:// 로 시작해야 해요"
        case .unauthorized: "토큰이 맞지 않아요"
        case .http(let code): "서버 응답 \(code)"
        }
    }
}

enum StatusClient {
    static func fetch(_ source: StatusSource) async throws -> NasStatus {
        if source.badURL { throw StatusError.badURL }
        guard let url = source.url else { throw StatusError.noURL }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        if let token = source.token { req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        let (data, resp) = try await URLSession.shared.data(for: req)
        if let code = (resp as? HTTPURLResponse)?.statusCode, code >= 400 {
            throw code == 401 ? StatusError.unauthorized : StatusError.http(code)
        }
        return try JSONDecoder().decode(NasStatus.self, from: data)
    }
}

func levelColor(_ v: Int) -> Color {
    v >= 90 ? .red : v >= 70 ? .yellow : .green
}

func tempColor(_ v: Int) -> Color {
    v >= 90 ? .red : v >= 75 ? .yellow : .green
}
