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
    /// 홈을 못 찾으면 nil — 컨테이너 홈으로 대신 쓰면 위젯이 못 읽는 곳에 조용히 저장된다.
    static var fileURL: URL? {
        var pw = passwd(), result: UnsafeMutablePointer<passwd>?
        var buf = [CChar](repeating: 0, count: 4096)
        guard getpwuid_r(getuid(), &pw, &buf, buf.count, &result) == 0, result != nil, let dir = pw.pw_dir else { return nil }
        return URL(fileURLWithPath: String(cString: dir)).appendingPathComponent("Library/Application Support/NasWidget/config.json")
    }

    static func load() -> SavedConfig? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(SavedConfig.self, from: data)
    }

    static func save(_ config: SavedConfig) throws {
        guard let fileURL else { throw CocoaError(.fileNoSuchFile) }
        let dir = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true,
                                                attributes: [.posixPermissions: 0o700])
        try JSONEncoder().encode(config).write(to: fileURL, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: fileURL.path)
    }
}
