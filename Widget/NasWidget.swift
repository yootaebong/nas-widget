import SwiftUI
import WidgetKit

struct Entry: TimelineEntry {
    var date: Date
    var status: NasStatus?
    var error: String?
}

struct Provider: TimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, status: .sample) }

    func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
        if context.isPreview { completion(placeholder(in: context)); return }
        Task { completion(await load()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
        Task {
            let e = await load()
            completion(Timeline(entries: [e], policy: .after(.now.addingTimeInterval(300))))
        }
    }

    private func load() async -> Entry {
        do { return Entry(date: .now, status: try await StatusClient.fetch()) }
        catch { return Entry(date: .now, status: nil, error: "NAS 에 연결 못 함 (네트워크 확인)") }
    }
}

struct NasWidgetView: View {
    @Environment(\.widgetFamily) var family
    var entry: Entry

    var body: some View {
        Group {
            if let s = entry.status {
                switch family {
                case .systemSmall:
                    VStack(spacing: 4) {
                        if (s.firing ?? 0) > 0 { AlertBanner(status: s) }
                        if let nas = s.systems.first { DiskRing(system: nas) }
                    }
                case .systemMedium:
                    VStack(alignment: .leading, spacing: 6) {
                        header("서비스", s)
                        AlertBanner(status: s)
                        ServicesView(status: s, columns: 2)
                        ContainersView(status: s)
                    }
                default:
                    VStack(alignment: .leading, spacing: 8) {
                        header("기기 \(s.systems.count)대", s)
                        AlertBanner(status: s)
                        SystemsView(status: s)
                        Divider()
                        ServicesView(status: s, columns: 2)
                        Divider()
                        ContainersView(status: s)
                        Spacer(minLength: 0)
                    }
                }
            } else {
                VStack(spacing: 6) {
                    Image(systemName: "wifi.exclamationmark").font(.title2)
                    Text(entry.error ?? "불러오는 중").font(.caption).multilineTextAlignment(.center)
                }.foregroundStyle(.secondary)
            }
        }
        .containerBackground(.fill.tertiary, for: .widget)
        .widgetURL(dashboardURL)
    }

    func header(_ title: String, _ s: NasStatus) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
            AlertBadge(status: s)
            Spacer()
            Text(entry.date, style: .time).font(.system(size: 11)).foregroundStyle(.secondary)
        }
    }
}

@main
struct NasWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "NasWidget", provider: Provider()) { NasWidgetView(entry: $0) }
            .configurationDisplayName("NAS 상태")
            .description("기기별 CPU·메모리·디스크·온도와 서비스 상태")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
