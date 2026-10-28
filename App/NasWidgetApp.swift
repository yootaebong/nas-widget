import SwiftUI

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
            Text("위젯 추가: 바탕화면 우클릭 → 위젯 편집 → '서버 상태' 검색.\n위젯에는 위젯 우클릭 → '위젯 편집' 에서 같은 주소를 넣어요 (여기 칸은 연결 시험용).")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("연결 시험") { Task { await load() } }
                if let dashboard = source.dashboard {
                    Button("대시보드 열기") { NSWorkspace.shared.open(dashboard) }
                }
            }
        }
        .padding(16)
        .task { await load() }
    }

    func load() async {
        do { status = try await StatusClient.fetch(source); error = nil }
        catch { status = nil; self.error = "연결 못 함: \(error.localizedDescription)" }
    }
}
