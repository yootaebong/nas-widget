import SwiftUI
import WidgetKit

@main
struct NasWidgetApp: App {
    var body: some Scene {
        WindowGroup("서버 상태 위젯") { ContentView().frame(width: 360) }
            .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @AppStorage("statusURL") private var statusURL = ""
    @AppStorage("token") private var token = ""
    @AppStorage("dashboardURL") private var dashboardURL = ""
    @State private var status: NasStatus?
    @State private var error: String?
    @State private var saved = false

    private var source: StatusSource { StatusSource(url: statusURL, token: token, dashboard: dashboardURL) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                TextField("상태 주소 (예: http://192.168.0.10:8080/status)", text: $statusURL)
                SecureField("토큰 (선택)", text: $token)
                TextField("대시보드 주소 (선택)", text: $dashboardURL)
            }
            .textFieldStyle(.roundedBorder)
            .onSubmit { Task { await load() } }
            Divider()
            if let status {
                AlertBanner(status: status)
                SystemsView(status: status)
                Divider()
                ServicesView(status: status, columns: 2)
                Divider()
                ContainersView(status: status)
            } else {
                Text(error ?? "불러오는 중…").foregroundStyle(.secondary)
            }
            Divider()
            Text(saved ? "저장됨 — 바탕화면 위젯이 이 주소를 씁니다." : "연결 시험이 통과하면 이 값을 위젯이 그대로 씁니다.")
                .font(.caption).foregroundStyle(saved ? .green : .secondary)
            Text("위젯 추가: 바탕화면 우클릭 → 위젯 편집 → '서버 상태' 검색.\n위젯 편집 칸은 비워 두면 됩니다(넣으면 그 위젯만 그 값을 씁니다).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("연결 시험") { Task { await load() } }
                if let dashboard = source.dashboard {
                    Button("대시보드 열기") { NSWorkspace.shared.open(dashboard) }
                }
            }
        }
        .padding(16)
        .task {
            // 앱을 새로 깔았어도 위젯과 나눈 값이 있으면 채운다
            if statusURL.isEmpty, let c = SharedConfig.load() {
                statusURL = c.statusURL; token = c.token; dashboardURL = c.dashboardURL
            }
            await load()
        }
    }

    func load() async {
        do {
            status = try await StatusClient.fetch(source); error = nil
            saveForWidget()
        } catch { status = nil; saved = false; self.error = "연결 못 함: \(error.localizedDescription)" }
    }

    /// 연결 시험을 통과한 값만 위젯에 넘긴다 — 틀린 값으로 위젯이 깨지지 않게
    func saveForWidget() {
        let c = SavedConfig(statusURL: statusURL.trimmingCharacters(in: .whitespacesAndNewlines),
                            token: token.trimmingCharacters(in: .whitespacesAndNewlines),
                            dashboardURL: dashboardURL.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !c.statusURL.isEmpty else { saved = false; return }
        do {
            if SharedConfig.load() != c {
                try SharedConfig.save(c)
                WidgetCenter.shared.reloadAllTimelines()
            }
            saved = true
        } catch {
            saved = false; self.error = "위젯에 넘기지 못함: \(error.localizedDescription)"
        }
    }
}
