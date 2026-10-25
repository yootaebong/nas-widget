import Foundation
import SwiftUI

struct NasStatus: Codable {
    struct System: Codable, Identifiable {
        var name: String
        var up: Bool
        var cpu: Int
        var mem: Int
        var disk: Int
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
        systems: [.init(name: "NAS", up: true, cpu: 12, mem: 37, disk: 84),
                  .init(name: "맥북", up: true, cpu: 45, mem: 75, disk: 74),
                  .init(name: "데스크톱", up: true, cpu: 64, mem: 57, disk: 52)],
        services: [.init(name: "웹", ok: true, value: "56ms"), .init(name: "Redis", ok: true, value: nil),
                   .init(name: "DB", ok: true, value: nil), .init(name: "인터넷", ok: true, value: "7ms")],
        firing: 1, firing_names: ["웹 응답 느림"], relay_connections: 14,
        containers: [.init(name: "postgres", mem_mb: 1830), .init(name: "redis", mem_mb: 389),
                     .init(name: "grafana", mem_mb: 301)])
}

/// 앱 버튼과 위젯 탭으로 여는 대시보드 주소. `Local.xcconfig` 의 `DASHBOARD_URL` 이 비었거나 잘못되면 nil.
let dashboardURL: URL? = (Bundle.main.object(forInfoDictionaryKey: "DashboardURL") as? String)
    .flatMap { URL(string: $0) }
    .flatMap { $0.scheme == nil ? nil : $0 }

func memText(_ mb: Int) -> String {
    mb >= 1024 ? String(format: "%.1fGB", Double(mb) / 1024) : "\(mb)MB"
}

enum StatusClient {
    static var url: URL? {
        (Bundle.main.object(forInfoDictionaryKey: "NASStatusURL") as? String).flatMap(URL.init(string:))
    }

    static func fetch() async throws -> NasStatus {
        guard let url else { throw URLError(.badURL) }
        var req = URLRequest(url: url)
        req.timeoutInterval = 20
        let (data, _) = try await URLSession.shared.data(for: req)
        return try JSONDecoder().decode(NasStatus.self, from: data)
    }
}

func levelColor(_ v: Int) -> Color {
    v >= 90 ? .red : v >= 70 ? .yellow : .green
}
