import AppIntents
import SwiftUI
import WidgetKit

/// 위젯 우클릭 → "위젯 편집" 에서 넣는 값. 비우면 앱 창에서 연결 시험을 통과한 값, 그것도 없으면 빌드 때 `Local.xcconfig` 값을 쓴다.
struct NasWidgetConfig: WidgetConfigurationIntent {
    static var title: LocalizedStringResource = "서버 상태 위젯 설정"
    static var description = IntentDescription("상태 JSON 주소와 토큰을 넣습니다.")

    @Parameter(title: "상태 주소", description: "예: http://192.168.0.10:8080/status")
    var statusURL: String?

    @Parameter(title: "토큰 (선택)")
    var token: String?

    @Parameter(title: "대시보드 주소 (선택)", description: "위젯을 누르면 열 주소")
    var dashboardURL: String?

    var source: StatusSource {
        if nonEmpty(statusURL) == nil, let c = SharedConfig.load() {
            return StatusSource(url: c.statusURL, token: c.token, dashboard: c.dashboardURL)
        }
        return StatusSource(url: statusURL, token: token, dashboard: dashboardURL)
    }
}

struct Entry: TimelineEntry {
    var date: Date
    var status: NasStatus?
    var error: String?
    var dashboard: URL?
}

struct Provider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> Entry { Entry(date: .now, status: .sample) }

    func snapshot(for configuration: NasWidgetConfig, in context: Context) async -> Entry {
        context.isPreview ? placeholder(in: context) : await load(configuration.source)
    }

    func timeline(for configuration: NasWidgetConfig, in context: Context) async -> Timeline<Entry> {
        Timeline(entries: [await load(configuration.source)], policy: .after(.now.addingTimeInterval(300)))
    }

    private func load(_ source: StatusSource) async -> Entry {
        if source.badURL {
            return Entry(date: .now, error: "상태 주소는 http:// 또는 https:// 로 시작해야 해요", dashboard: source.dashboard)
        }
        guard source.url != nil else {
            return Entry(date: .now, error: "서버 상태 위젯 앱을 열어 주소를 넣고 연결 시험을 눌러 주세요", dashboard: source.dashboard)
        }
        do { return Entry(date: .now, status: try await StatusClient.fetch(source), dashboard: source.dashboard) }
        catch StatusError.insecurePublic {
            return Entry(date: .now, error: "공개 주소는 https:// 로 (앱에서 확인)", dashboard: source.dashboard)
        } catch StatusError.unauthorized {
            return Entry(date: .now, error: "토큰이 맞지 않아요 (앱에서 확인)", dashboard: source.dashboard)
        } catch {
            return Entry(date: .now, error: "중앙 서버에 연결 못 함 (네트워크 확인)", dashboard: source.dashboard)
        }
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
        .widgetURL(entry.dashboard)
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
        AppIntentConfiguration(kind: "NasWidget", intent: NasWidgetConfig.self, provider: Provider()) { NasWidgetView(entry: $0) }
            .configurationDisplayName("서버 상태")
            .description("기기별 CPU·메모리·디스크·온도와 서비스 상태")
            .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
