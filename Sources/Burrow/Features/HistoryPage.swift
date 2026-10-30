import SwiftUI

struct HistoryPage: View {
    @ViewState private var history: HistoryResult?
    @ViewState private var loading = true
    @ViewState private var error: String?
    /// Previews (dry runs) are what Burrow runs on every visit; real changes are what matter here.
    @AppStorage("history.showPreviews") private var showPreviews = false

    private var all: [HistoryResult.Session] { history?.sessions ?? [] }
    private var sessions: [HistoryResult.Session] { showPreviews ? all : all.filter(\.changedSomething) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Text(summary).caption()
                Spacer()
                Toggle("Show previews and empty runs", isOn: $showPreviews).toggleStyle(.switch).controlSize(.small)
                CircleIconButton(symbol: "arrow.clockwise", help: "Reload") { Task { await load() } }
                    .keyboardShortcut("r", modifiers: .command)
                CircleIconButton(symbol: "doc.text.magnifyingglass", help: "Open Mole's logs") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: ("~/Library/Logs/mole" as NSString).expandingTildeInPath))
                }
            }
            if !sessions.isEmpty {
                LazyVStack(spacing: 0) {
                    ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                        row(s, last: i == sessions.count - 1)
                    }
                }
                .animation(Motion.spring, value: showPreviews)
            } else if let error {
                EmptyState(symbol: "exclamationmark.triangle", text: "Mole could not read its history", detail: error,
                           actionTitle: "Try again") { Task { await load() } }
            } else if loading {
                EmptyState(symbol: "hourglass", text: "Reading Mole's history…")
            } else {
                EmptyState(symbol: "clock", text: all.isEmpty ? "Nothing yet." : "No changes yet.",
                           detail: all.isEmpty ? "Runs appear here after you clean, uninstall or optimize."
                                               : "\(all.count) previews ran, but nothing was changed.",
                           actionTitle: all.isEmpty ? nil : "Show previews") { showPreviews = true }
            }
        }
        .onAppear { Task { await load() } }
    }

    private var summary: String {
        let hidden = all.count - sessions.count
        return "\(sessions.count) run\(sessions.count == 1 ? "" : "s")" + (hidden > 0 ? " · \(hidden) previews hidden" : "")
    }

    private func row(_ s: HistoryResult.Session, last: Bool) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(spacing: 0) {
                Circle().fill(glow(s).color).frame(width: 10, height: 10).padding(.top, 24)
                    .shadow(color: glow(s).color.opacity(0.8), radius: 6)
                if !last { Rectangle().fill(Theme.hairline).frame(width: 1) }
            }
            .frame(width: 10)
            GlowCard(glow: glow(s), style: .plain, padding: 18) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 8) {
                            Text(s.title).cardTitle()
                            if s.isPreview { Tag(text: "Preview") }
                            if s.looksInterrupted { Tag(text: "Interrupted", color: .orange) }
                        }
                        Text(s.when).caption()
                        if let a = s.actions {
                            HStack(spacing: 6) {
                                if let n = a.removed, n > 0 { Tag(text: "\(n) removed", color: Theme.accent) }
                                if let n = a.trashed, n > 0 { Tag(text: "\(n) to Trash") }
                                if let n = a.skipped, n > 0, !s.isPreview { Tag(text: "\(n) skipped", color: .orange) }
                                if let n = a.failed, n > 0 { Tag(text: "\(n) failed", color: Theme.danger) }
                                if let n = a.rebuilt, n > 0 { Tag(text: "\(n) rebuilt", color: Glow.blue.color) }
                            }
                        }
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text(s.size ?? "").font(.system(size: 20, weight: .semibold)).monospacedDigit()
                        Text("\(s.items ?? 0) items").caption()
                    }
                }
            }
            .padding(.bottom, 12)
        }
        .accessibilityElement(children: .combine)
    }

    private func load() async {
        loading = true
        do {
            history = try await Mole.json(HistoryResult.self, ["history", "--json", "--limit", "200"])
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
        loading = false
    }

    private func glow(_ s: HistoryResult.Session) -> Glow {
        switch s.baseCommand {
        case "clean": .magenta
        case "uninstall": .ember
        case "optimize": .sage
        case "purge": .blue
        case "slim": .magenta
        default: .violet
        }
    }
}

extension HistoryResult.Session {
    /// "clean-dry-run" → "clean".
    var baseCommand: String { command.replacingOccurrences(of: "-dry-run", with: "") }
    var isPreview: Bool { command.hasSuffix("-dry-run") }
    var title: String {
        switch baseCommand {
        case "purge": "Project build folders"
        case "slim": "Slim apps"
        default: baseCommand.capitalized
        }
    }

    /// A real run that removed, trashed, rebuilt or failed something.
    var changedSomething: Bool {
        guard !isPreview else { return false }
        let a = actions
        return (items ?? 0) > 0 || [a?.removed, a?.trashed, a?.rebuilt, a?.failed].contains { ($0 ?? 0) > 0 }
    }

    var startedDate: Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.date(from: started_at)
    }

    /// No end time and started over an hour ago. A run without an end time that began recently
    /// may simply still be running.
    var looksInterrupted: Bool {
        guard ended_at?.isEmpty ?? true, let start = startedDate else { return false }
        return Date().timeIntervalSince(start) > 3600
    }

    /// "Today, 03:20" from Mole's "2026-10-30 03:20:38".
    var when: String {
        guard let date = startedDate else { return started_at }
        return date.formatted(.relative(presentation: .named)) + " · " + date.formatted(date: .abbreviated, time: .shortened)
    }
}
