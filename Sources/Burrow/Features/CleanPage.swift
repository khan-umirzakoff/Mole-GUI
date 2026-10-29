import SwiftUI

struct CleanPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scan: Scan<SectionReport>
    @AppStorage("clean.includeSystem") private var includeSystem = false
    @ViewState private var confirm: ConfirmAction?

    var body: some View {
        let report = scan.current
        VStack(alignment: .leading, spacing: 22) {
            HeroCard(glow: .magenta, label: scan.scanning ? "Found so far" : "Ready to clean", bytes: report?.bytes,
                     detail: scan.report?.summary.first(where: { $0.contains("Potential") }) ?? "Mole previews everything first. Nothing is removed until you press Clean.",
                     scanning: scan.scanning, progress: progress, started: scan.startedAt, error: scan.error) {
                ScanButton(scanning: scan.scanning, start: scan.start, stop: scan.cancel)
                Button("Clean now") { askToClean() }
                    .buttonStyle(.pill)
                    .disabled(scan.scanning || (scan.report?.bytes ?? 0) == 0)
            }

            HStack(spacing: 14) {
                Toggle(isOn: $includeSystem) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include system caches").font(.system(size: 13, weight: .medium))
                        Text("Mole asks for your administrator password while cleaning").caption()
                    }
                }
                .toggleStyle(.switch)
                Spacer()
                Button { model.page = .settings } label: { Label("Protected paths", systemImage: "lock.shield") }
                    .buttonStyle(.pillSecondary)
            }

            if let report {
                Notes(notes: report.notes.filter { !$0.contains("System caches need sudo") })
                if report.sections.isEmpty, !scan.scanning {
                    EmptyState(symbol: "checkmark.seal", text: "Nothing to clean right now.")
                } else {
                    SectionGrid(sections: report.sections, glow: .magenta)
                }
            } else if scan.error != nil {
                EmptyState(symbol: "exclamationmark.triangle", text: "The preview did not finish",
                           detail: scan.error ?? "", actionTitle: "Try again", action: scan.start)
            }
        }
        .confirmation($confirm)
        .onAppear(perform: scan.startIfNeeded)
    }

    private var progress: String {
        [scan.section, scan.status].filter { !$0.isEmpty }.joined(separator: " · ")
    }

    private func askToClean() {
        let size = scan.report?.bytes.bytesText ?? ""
        confirm = .init(title: "Clean \(size)?",
                        message: "Mole removes the caches and logs listed here. Protected paths are skipped."
                            + (includeSystem ? " System caches need your administrator password." : ""),
                        button: "Clean") {
            model.run("Cleaning your Mac", ["clean"],
                      responders: [.when("System caches need sudo", send: includeSystem ? "\r" : " ")]) {
                scan.start()
            }
        }
    }
}

/// "Rescan" that turns into "Stop" while Mole is scanning. ⌘R either way.
struct ScanButton: View {
    let scanning: Bool
    var title = "Rescan"
    let start: () -> Void
    let stop: () -> Void

    var body: some View {
        Button(scanning ? "Stop" : title) { scanning ? stop() : start() }
            .buttonStyle(.pillSecondary)
            .keyboardShortcut("r", modifiers: .command)
            .help(scanning ? "Stop the scan (⌘R)" : "Scan again (⌘R)")
    }
}

struct OptimizePage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scan: Scan<SectionReport>

    var body: some View {
        let report = scan.current
        VStack(alignment: .leading, spacing: 22) {
            GlowCard(glow: .sage, style: .rim, padding: 26) {
                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        Text("Maintenance").cardTitle()
                        Spacer()
                        if scan.scanning { ScanningBadge(started: scan.startedAt).transition(.blurFade) }
                    }
                    HStack(alignment: .bottom, spacing: 16) {
                        VStack(alignment: .leading, spacing: 12) {
                            Group {
                                if scan.error != nil, !scan.scanning {
                                    Label("Mole could not finish", systemImage: "exclamationmark.triangle.fill")
                                        .font(.system(size: 24, weight: .semibold)).symbolRenderingMode(.multicolor)
                                } else if scan.report == nil {
                                    Text(scan.scanning ? "Checking…" : "Not checked yet")
                                        .font(.system(size: 26, weight: .medium)).shimmer(scan.scanning)
                                } else {
                                    MetricValue(value: "\(pendingSteps)", unit: pendingSteps == 1 ? "step to run" : "steps to run", dot: 7)
                                }
                            }
                            .frame(height: 80, alignment: .bottomLeading)
                            Text(footnote).font(.system(size: 12))
                                .foregroundStyle(scan.error != nil && !scan.scanning ? Theme.danger : Theme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer(minLength: 12)
                        HStack(spacing: 10) {
                            ScanButton(scanning: scan.scanning, title: "Recheck", start: scan.start, stop: scan.cancel)
                            Button("Optimize") {
                                model.run("Optimizing", ["optimize"]) { scan.start() }
                            }
                            .buttonStyle(.pill).disabled(scan.scanning || scan.report == nil)
                        }
                        .fixedSize()
                    }
                }
            }
            .frame(height: 216)
            .animation(Motion.spring, value: scan.scanning)

            if let report {
                if !report.notes.isEmpty {
                    GlowCard(glow: .ember, style: .core, padding: 20) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Performance diagnosis").cardTitle()
                            Notes(notes: report.notes)
                        }
                    }
                }
                SectionGrid(sections: report.sections, glow: .sage)
            } else if scan.error != nil {
                EmptyState(symbol: "exclamationmark.triangle", text: "The check did not finish",
                           detail: scan.error ?? "", actionTitle: "Try again", action: scan.start)
            }
        }
        .onAppear(perform: scan.startIfNeeded)
    }

    private var footnote: String {
        if scan.scanning { return scan.section.isEmpty ? "Mole is looking at your system…" : "Checking \(scan.section)" }
        if let error = scan.error { return error }
        if let tally = scan.report?.summary.first(where: { $0.contains("unchanged") }) { return tally.replacingOccurrences(of: " | ", with: " · ") }
        return "Finder, DNS, Spotlight, preferences and more. Mole asks before anything needs your password."
    }

    /// Steps Mole would run, from its "Would apply N optimizations" summary.
    private var pendingSteps: Int {
        let line = scan.report?.summary.first { $0.contains("Would apply") } ?? ""
        return line.split(separator: " ").compactMap { Int($0) }.first ?? 0
    }
}
