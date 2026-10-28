import SwiftUI
import WidgetKit

/// 글자 색(앱·위젯 공용). 창이 앞에 오면 맥은 위젯을 다시 그리지 않고 다 그린 그림에 단색 필터만 씌운다 — 어두운 색은 진하게,
/// 밝은 색은 투명하게(1.12 맥북 색 시험). 그래서 위젯은 밝은 외관으로 고정하고(NasWidget) 여기선 계층 색만 쓴다.
struct Ink: ViewModifier {
    var secondary = false
    func body(content: Content) -> some View {
        content.foregroundStyle(secondary ? AnyShapeStyle(.secondary) : AnyShapeStyle(.primary))
    }
}

extension View {
    func ink(secondary: Bool = false) -> some View { modifier(Ink(secondary: secondary)) }
}

struct Bar: View {
    var label: String
    var value: Int
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).ink(secondary: true).frame(width: 40, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(levelColor(value)).frame(width: g.size.width * CGFloat(min(value, 100)) / 100)
                }
            }.frame(height: 6)
            Text("\(value)%").font(.system(size: 11).monospacedDigit()).ink().frame(width: 34, alignment: .trailing)
        }
    }
}

struct Dot: View {
    var ok: Bool
    var neutral = false
    var body: some View { Circle().fill(neutral ? Color.secondary : ok ? Color.green : Color.red).frame(width: 7, height: 7) }
}

/// 위 칸 이름, 아래 숫자(수준별 색). 기기 줄의 한 칸.
struct Metric: View {
    var label: String
    var text: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).ink(secondary: true).lineLimit(1)
            Text(text).font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(color).lineLimit(1).minimumScaleFactor(0.8)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension Metric {
    init(label: String, value: Int) { self.init(label: label, text: "\(value)%", color: levelColor(value)) }
    /// 기기 온도(가장 뜨거운 센서). 못 읽으면 "-".
    init(temp: Int?) { self.init(label: "온도", text: temp.map { "\($0)°" } ?? "-", color: temp.map(tempColor) ?? .secondary) }
}

struct SystemsView: View {
    var status: NasStatus
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(status.systems) { s in
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Dot(ok: s.up)
                        Text(s.name).font(.system(size: 11, weight: .semibold)).ink().lineLimit(1).minimumScaleFactor(0.8)
                    }.frame(width: 72, alignment: .leading)
                    Metric(label: "CPU", value: s.cpu)
                    Metric(label: "메모리", value: s.mem)
                    Metric(label: "디스크", value: s.disk)
                    Metric(temp: s.temp)
                }
            }
        }
    }
}

struct ServiceRow: View {
    var name: String
    var ok: Bool
    var text: String
    /// 판정 없는 값 줄 — 정상이면 회색으로 값만 보인다
    var info = false
    var body: some View {
        let neutral = info && ok
        HStack(spacing: 4) {
            Text(name).font(.system(size: 11)).ink().lineLimit(1)
            Spacer(minLength: 2)
            Dot(ok: ok, neutral: neutral)
            Text(text).font(.system(size: 11).monospacedDigit())
                .foregroundStyle(neutral ? Color.secondary : ok ? Color.green : Color.red).lineLimit(1)
        }
    }
}

struct ServicesView: View {
    var status: NasStatus
    var columns = 1
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), alignment: .leading, spacing: 5) {
            ForEach(status.services) { s in
                let info = s.info ?? false
                ServiceRow(name: s.name, ok: s.ok, text: s.value ?? (s.ok ? "정상" : info ? "못 읽음" : "죽음"), info: info)
            }
            if let n = status.relay_connections {
                ServiceRow(name: "relay 연결", ok: n > 0, text: "\(n)개")
            }
        }
    }
}

struct AlertBanner: View {
    var status: NasStatus
    var body: some View {
        let n = status.firing ?? 0
        if n > 0 {
            HStack(spacing: 5) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10))
                Text("알림 \(n)건 · " + (status.firing_names ?? []).joined(separator: ", "))
                    .font(.system(size: 11, weight: .semibold)).lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(.red)
        }
    }
}

struct AlertBadge: View {
    var status: NasStatus
    var body: some View {
        if let n = status.firing, n == 0 {
            Text("알림 없음").font(.system(size: 10)).foregroundStyle(.green)
        } else if status.firing == nil {
            Text("알림 모름").font(.system(size: 10)).ink(secondary: true)
        }
    }
}

struct ContainersView: View {
    var status: NasStatus
    var body: some View {
        if let cs = status.containers, !cs.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("도커 메모리 상위").font(.system(size: 9)).ink(secondary: true)
                HStack(spacing: 10) {
                    ForEach(cs) { c in
                        HStack(spacing: 3) {
                            Text(c.name)
                                .font(.system(size: 11)).ink().lineLimit(1)
                            Text(memText(c.mem_mb)).font(.system(size: 11, weight: .semibold).monospacedDigit()).ink()
                        }
                    }
                }
            }
        }
    }
}

struct DiskRing: View {
    var system: NasStatus.System
    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 5) { Dot(ok: system.up); Text(system.name).font(.system(size: 12, weight: .semibold)).ink(); Spacer() }
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 9)
                Circle().trim(from: 0, to: CGFloat(system.disk) / 100)
                    .stroke(levelColor(system.disk), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(system.disk)%").font(.system(size: 22, weight: .bold).monospacedDigit()).ink()
                    Text("디스크").font(.system(size: 10)).ink(secondary: true)
                }
            }.padding(.horizontal, 10)
            Text("CPU \(system.cpu)% · 메모리 \(system.mem)%" + (system.temp.map { " · \($0)°" } ?? "")).font(.system(size: 10)).ink(secondary: true)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}
