import SwiftUI

struct CleanPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scan: Scan<SectionReport>
    @AppStorage("clean.includeSystem") private var includeSystem = false
    @ViewState private var confirm: ConfirmAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HeroCard(glow: .magenta, label: "Ready to clean", bytes: scan.report?.bytes,
                     detail: scan.report?.summary.first ?? "Mole previews everything first. Nothing is removed until you press Clean.",
                     scanning: scan.scanning) {
                Button("Rescan") { Task { await rescan() } }.buttonStyle(.pillSecondary).disabled(scan.scanning)
                Button("Clean now") { askToClean() }.buttonStyle(.pill).disabled(scan.report == nil || scan.scanning)
            }

            HStack(spacing: 14) {
                Toggle(isOn: $includeSystem) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include system caches").font(.system(size: 13, weight: .medium))
                        Text("Needs your administrator password while cleaning").caption()
                    }
                }
                .toggleStyle(.switch)
                Spacer()
                Button { model.page = .settings } label: { Label("Protected paths", systemImage: "lock.shield") }
                    .buttonStyle(.pillSecondary)
            }

            if let report = scan.report {
                Notes(notes: report.notes)
                if report.sections.isEmpty {
                    EmptyState(symbol: "checkmark.seal", text: "Nothing to clean right now.")
                } else {
                    SectionGrid(sections: report.sections, glow: .magenta)
                }
            }
        }
        .confirmation($confirm)
        .task { if scan.report == nil { await rescan() } }
    }

    private func rescan() async { await scan.run() }

    private func askToClean() {
        let size = scan.report?.bytes.bytesText ?? ""
        confirm = .init(title: "Clean \(size)?",
                        message: "Mole removes the caches and logs listed here. Protected paths are skipped.",
                        button: "Clean") {
            model.run("Cleaning your Mac", ["clean"],
                      responders: [.when("System caches need sudo", send: includeSystem ? "\r" : " ")]) {
                Task { await rescan() }
            }
        }
    }
}

struct OptimizePage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scan: Scan<SectionReport>

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            GlowCard(glow: .sage, style: .rim, padding: 26) {
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 14) {
                        Text("Maintenance").cardTitle()
                        if scan.scanning {
                            HStack(spacing: 12) {
                                ProgressView().controlSize(.small).tint(.white)
                                Text("Checking…").font(.system(size: 22, weight: .medium)).shimmer()
                            }
                        } else {
                            MetricValue(value: pendingSteps, unit: "steps to run", dot: 7)
                        }
                        Text(scan.report?.summary.dropFirst().first ?? "Finder, DNS, Spotlight, preferences and more.").caption()
                    }
                    Spacer()
                    Button("Recheck") { Task { await scan.run() } }.buttonStyle(.pillSecondary).disabled(scan.scanning)
                    Button("Optimize") {
                        model.run("Optimizing", ["optimize"]) { Task { await scan.run() } }
                    }
                    .buttonStyle(.pill).disabled(scan.scanning)
                }
            }
            .frame(height: 200)

            if let report = scan.report {
                if !report.notes.isEmpty {
                    GlowCard(glow: .ember, style: .core, padding: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Performance diagnosis").cardTitle()
                            Notes(notes: report.notes)
                        }
                    }
                }
                SectionGrid(sections: report.sections, glow: .sage)
            }
        }
        .task { if scan.report == nil { await scan.run() } }
    }

    /// "Would apply 3 optimizations" from Mole's summary.
    private var pendingSteps: String {
        let line = scan.report?.summary.first { $0.contains("Would apply") } ?? ""
        return line.split(separator: " ").first { Int($0) != nil }.map(String.init) ?? "0"
    }
}
