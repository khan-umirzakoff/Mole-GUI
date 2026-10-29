import SwiftUI

/// Streams `mo status --watch` while the overview is on screen.
@MainActor
final class StatusMonitor: ObservableObject {
    @Published var status: SystemStatus?
    @Published var rxHistory: [Double] = []
    @Published var cpuHistory: [Double] = []
    private var stream: Mole.LineStream?

    func start() {
        guard stream == nil else { return }
        stream = Mole.LineStream(["status", "--watch", "--interval", "2s"]) { [weak self] line in
            guard let self, let data = line.data(using: .utf8),
                  let s = try? JSONDecoder().decode(SystemStatus.self, from: data) else { return }
            self.status = s
            let rx = (s.network ?? []).compactMap(\.rx_rate_mbs).reduce(0, +)
            self.rxHistory = Array((self.rxHistory + [rx]).suffix(32))
            self.cpuHistory = Array((self.cpuHistory + [s.cpu?.usage ?? 0]).suffix(32))
        }
    }

    func stop() {
        stream?.stop()
        stream = nil
    }
}

struct OverviewPage: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var monitor = StatusMonitor()

    var body: some View {
        let s = monitor.status
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                diskCard(s).frame(maxWidth: .infinity)
                healthCard(s).frame(width: 330)
            }
            .frame(height: 250)

            HStack(spacing: 18) {
                cpuCard(s)
                memoryCard(s)
                batteryCard(s)
                networkCard
            }
            .frame(height: 210)

            HStack(spacing: 18) {
                processesCard(s).frame(maxWidth: .infinity)
                VStack(spacing: 18) {
                    QuickAction(title: "Clean caches", value: model.clean.report.map { $0.bytes.bytesText } ?? "Scan",
                                glow: .magenta) { model.page = .clean }
                    QuickAction(title: "Project build folders", value: model.purge.report.map { $0.bytes.bytesText } ?? "Scan",
                                glow: .blue) { model.page = .projects }
                    QuickAction(title: "Old installers", value: model.installers.files.map { $0.map(\.bytes).reduce(0, +).bytesText } ?? "Scan",
                                glow: .ember) { model.page = .installers }
                }
                .frame(width: 330)
            }
            .frame(height: 300)
        }
        .redacted(reason: s == nil ? .placeholder : [])
        .onAppear { monitor.start() }
        .onDisappear { monitor.stop() }
    }

    private func diskCard(_ s: SystemStatus?) -> some View {
        let disk = s?.rootDisk
        let free = (disk?.total ?? 0) - (disk?.used ?? 0)
        let used = disk.map { Double($0.used) / Double(max($0.total, 1)) } ?? 0
        return GlowCard(glow: .blue, style: .rim) {
            VStack(alignment: .leading) {
                HStack {
                    Text("Free space").cardTitle()
                    Spacer()
                    if let p = disk?.purgeable, p > 0 { Tag(text: "\(p.bytesText) purgeable") }
                }
                Spacer()
                MetricValue(value: free.metric.value, unit: free.metric.unit + " free", dot: 7)
                Spacer()
                DotMeter(value: used, count: 48)
                HStack {
                    Text("\(disk?.used.bytesText ?? "–") used").caption()
                    Spacer()
                    Text("\(disk?.total.bytesText ?? "–") total").caption()
                }
            }
        }
    }

    private func healthCard(_ s: SystemStatus?) -> some View {
        let score = s?.health_score ?? 0
        return GlowCard(glow: .sage, style: .core) {
            VStack(alignment: .leading) {
                Text("Health score").cardTitle()
                ZStack(alignment: .bottom) {
                    ArcTicks(value: Double(score) / 100, color: score >= 70 ? Theme.accent : score >= 45 ? .orange : Theme.danger)
                    VStack(spacing: 6) {
                        DotMatrixText(text: "\(score)", dot: 5)
                        Text(s?.health_score_msg ?? "").caption().lineLimit(1)
                    }
                }
            }
        }
    }

    private func cpuCard(_ s: SystemStatus?) -> some View {
        GlowCard(glow: .violet, style: .core, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("CPU").cardTitle(); Spacer(); Text(s?.hardware?.cpu_model ?? "").caption() }
                MetricValue(value: String(format: "%.0f", s?.cpu?.usage ?? 0), unit: "%", dot: 4.5)
                BarSpark(values: s?.cpu?.per_core ?? [], color: .white, maxValue: 100)
                Text("Load \(String(format: "%.2f", s?.cpu?.load1 ?? 0)) · \(s?.procs ?? 0) processes").caption()
            }
        }
    }

    private func memoryCard(_ s: SystemStatus?) -> some View {
        let m = s?.memory
        return GlowCard(glow: .magenta, style: .rim, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Memory").cardTitle()
                Spacer()
                MetricValue(value: String(format: "%.0f", m?.used_percent ?? 0), unit: "%", dot: 4.5)
                DotMeter(value: (m?.used_percent ?? 0) / 100, count: 22)
                Text("\(m?.used.bytesText ?? "–") of \(m?.total.bytesText ?? "–")").caption()
            }
        }
    }

    private func batteryCard(_ s: SystemStatus?) -> some View {
        let b = s?.batteries?.first
        return GlowCard(glow: .ember, style: .core, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text("Battery").cardTitle(); Spacer(); if let st = b?.status { Tag(text: st) } }
                Spacer()
                MetricValue(value: String(format: "%.0f", b?.percent ?? 0), unit: "%", dot: 4.5)
                Text("\(b?.health ?? "–") · \(b?.cycle_count ?? 0) cycles").caption()
                if let w = s?.thermal?.system_power { Text(String(format: "Drawing %.1f W", w)).caption() }
            }
        }
    }

    private var networkCard: some View {
        let s = monitor.status
        let rx = (s?.network ?? []).compactMap(\.rx_rate_mbs).reduce(0, +)
        let tx = (s?.network ?? []).compactMap(\.tx_rate_mbs).reduce(0, +)
        return GlowCard(glow: .graphite, style: .core, padding: 18) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Network").cardTitle()
                MetricValue(value: String(format: "%.1f", rx), unit: "MB/s in", dot: 4.5)
                BarSpark(values: monitor.rxHistory, color: Theme.accent)
                Text(String(format: "%.2f MB/s out", tx)).caption()
            }
        }
    }

    private func processesCard(_ s: SystemStatus?) -> some View {
        GlowCard(glow: .graphite, style: .plain) {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("Busiest processes").cardTitle()
                    Spacer()
                    Text(s?.uptime.map { "Up \($0)" } ?? "").caption()
                }
                ForEach(s?.top_processes ?? []) { p in
                    HStack {
                        Text(p.name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        DotMeter(value: min(p.cpu / 100, 1), count: 16, color: p.cpu > 80 ? Glow.ember.color : .white)
                        Text(String(format: "%.0f%%", p.cpu)).font(.system(size: 12, design: .monospaced))
                            .foregroundStyle(Theme.secondaryText).frame(width: 46, alignment: .trailing)
                    }
                }
                Spacer(minLength: 0)
            }
        }
    }
}

struct QuickAction: View {
    let title: String
    let value: String
    let glow: Glow
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            GlowCard(glow: glow, style: .core, padding: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title).caption()
                        Text(value).font(.system(size: 20, weight: .semibold)).foregroundStyle(.white)
                    }
                    Spacer()
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 13, weight: .bold)).foregroundStyle(.black)
                        .frame(width: 32, height: 32).background(Circle().fill(.white))
                }
            }
        }
        .buttonStyle(.plain)
        .hoverLift()
    }
}
