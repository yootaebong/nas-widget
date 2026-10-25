import SwiftUI
import WidgetKit

@main
struct NasWidgetApp: App {
    var body: some Scene {
        WindowGroup("NAS 위젯") { ContentView().frame(width: 360) }
            .windowResizability(.contentSize)
    }
}

struct ContentView: View {
    @State private var status: NasStatus?
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            Text("위젯 추가: 바탕화면 우클릭 → 위젯 편집 → 'NAS 위젯' 검색").font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("새로고침") { Task { await load() } }
                if let dashboardURL {
                    Button("대시보드 열기") { NSWorkspace.shared.open(dashboardURL) }
                }
            }
        }
        .padding(16)
        .task { await load() }
    }

    func load() async {
        do { status = try await StatusClient.fetch(); error = nil }
        catch { self.error = "NAS 에 연결 못 함: \(error.localizedDescription)" }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
