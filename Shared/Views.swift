import SwiftUI

struct Bar: View {
    var label: String
    var value: Int
    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: 40, alignment: .leading)
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(.quaternary)
                    Capsule().fill(levelColor(value)).frame(width: g.size.width * CGFloat(min(value, 100)) / 100)
                }
            }.frame(height: 6)
            Text("\(value)%").font(.system(size: 11).monospacedDigit()).frame(width: 34, alignment: .trailing)
        }
    }
}

struct Dot: View {
    var ok: Bool
    var body: some View { Circle().fill(ok ? Color.green : Color.red).frame(width: 7, height: 7) }
}

/// 위 칸 이름, 아래 숫자(수준별 색). 기기 줄의 한 칸.
struct Metric: View {
    var label: String
    var text: String
    var color: Color
    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
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
                        Text(s.name).font(.system(size: 11, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.8)
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
    var body: some View {
        HStack(spacing: 4) {
            Text(name).font(.system(size: 11)).lineLimit(1)
            Spacer(minLength: 2)
            Dot(ok: ok)
            Text(text).font(.system(size: 11).monospacedDigit()).foregroundStyle(ok ? Color.green : Color.red).lineLimit(1)
        }
    }
}

struct ServicesView: View {
    var status: NasStatus
    var columns = 1
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14), count: columns), alignment: .leading, spacing: 5) {
            ForEach(status.services) { s in
                ServiceRow(name: s.name, ok: s.ok, text: s.ok ? (s.value ?? "정상") : "죽음")
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
            Text("알림 모름").font(.system(size: 10)).foregroundStyle(.secondary)
        }
    }
}

struct ContainersView: View {
    var status: NasStatus
    var body: some View {
        if let cs = status.containers, !cs.isEmpty {
            VStack(alignment: .leading, spacing: 3) {
                Text("NAS 도커 메모리 상위").font(.system(size: 9)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    ForEach(cs) { c in
                        HStack(spacing: 3) {
                            Text(c.name)
                                .font(.system(size: 11)).lineLimit(1)
                            Text(memText(c.mem_mb)).font(.system(size: 11, weight: .semibold).monospacedDigit())
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
            HStack(spacing: 5) { Dot(ok: system.up); Text(system.name).font(.system(size: 12, weight: .semibold)); Spacer() }
            ZStack {
                Circle().stroke(.quaternary, lineWidth: 9)
                Circle().trim(from: 0, to: CGFloat(system.disk) / 100)
                    .stroke(levelColor(system.disk), style: StrokeStyle(lineWidth: 9, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                VStack(spacing: 0) {
                    Text("\(system.disk)%").font(.system(size: 22, weight: .bold).monospacedDigit())
                    Text("디스크").font(.system(size: 10)).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 10)
            Text("CPU \(system.cpu)% · 메모리 \(system.mem)%" + (system.temp.map { " · \($0)°" } ?? "")).font(.system(size: 10)).foregroundStyle(.secondary)
                .lineLimit(1).minimumScaleFactor(0.75)
        }
    }
}
