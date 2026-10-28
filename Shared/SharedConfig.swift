import Foundation

/// 앱 창에서 "연결 시험" 을 통과한 설정. 앱이 쓰고 위젯이 읽는다.
/// 둘 다 샌드박스라 서로의 설정을 못 보므로, 샌드박스 예외로 연 한 경로에 파일로 둔다
/// (App Group 은 팀 ID 없는 ad-hoc 서명에서 "다른 앱 데이터 접근" 확인이 뜰 수 있어 쓰지 않는다).
struct SavedConfig: Codable, Equatable {
    var statusURL: String
    var token: String
    var dashboardURL: String
}

enum SharedConfig {
    /// 샌드박스 안의 홈은 컨테이너라, 실제 홈은 계정 정보에서 읽는다. entitlements 의 예외 경로와 같아야 한다.
    static var fileURL: URL {
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return URL(fileURLWithPath: home).appendingPathComponent("Library/Application Support/NasWidget/config.json")
    }

    static func load() -> SavedConfig? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(SavedConfig.self, from: data)
    }

    static func save(_ config: SavedConfig) throws {
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(config).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
