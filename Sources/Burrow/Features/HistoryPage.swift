import SwiftUI

struct HistoryPage: View {
    @ViewState private var history: HistoryResult?
    @ViewState private var loading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("\(history?.sessions?.count ?? 0) runs").caption()
                Spacer()
                CircleIconButton(symbol: "arrow.clockwise", help: "Reload") { Task { await load() } }
                CircleIconButton(symbol: "doc.text.magnifyingglass", help: "Open Mole's logs") {
                    NSWorkspace.shared.open(URL(fileURLWithPath: ("~/Library/Logs/mole" as NSString).expandingTildeInPath))
                }
            }
            if let sessions = history?.sessions, !sessions.isEmpty {
                ForEach(Array(sessions.enumerated()), id: \.element.id) { i, s in
                    HStack(alignment: .top, spacing: 16) {
                        VStack(spacing: 0) {
                            Circle().fill(color(s.command)).frame(width: 10, height: 10).padding(.top, 22)
                            if i < sessions.count - 1 { Rectangle().fill(Theme.hairline).frame(width: 1) }
                        }
                        .frame(width: 10)
                        GlowCard(glow: glow(s.command), style: .plain, padding: 18) {
                            HStack(alignment: .top) {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(s.command.capitalized).cardTitle()
                                    Text(s.started_at).caption()
                                    HStack(spacing: 6) {
                                        if let a = s.actions {
                                            if (a.removed ?? 0) > 0 { Tag(text: "\(a.removed!) removed", color: Theme.accent) }
                                            if (a.trashed ?? 0) > 0 { Tag(text: "\(a.trashed!) to Trash") }
                                            if (a.skipped ?? 0) > 0 { Tag(text: "\(a.skipped!) skipped", color: .orange) }
                                            if (a.failed ?? 0) > 0 { Tag(text: "\(a.failed!) failed", color: Theme.danger) }
                                            if (a.rebuilt ?? 0) > 0 { Tag(text: "\(a.rebuilt!) rebuilt", color: Glow.blue.color) }
                                        }
                                    }
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 4) {
                                    Text(s.size ?? "").font(.system(size: 20, weight: .semibold))
                                    Text("\(s.items ?? 0) items").caption()
                                }
                            }
                        }
                    }
                }
            } else {
                EmptyState(symbol: "clock", text: loading ? "Reading Mole's history…" : "Nothing yet. Runs appear here after you clean.")
            }
        }
        .task { await load() }
    }

    private func load() async {
        loading = true
        history = try? await Mole.json(HistoryResult.self, ["history", "--json", "--limit", "200"])
        loading = false
    }

    private func glow(_ command: String) -> Glow {
        switch command {
        case "clean": .magenta
        case "uninstall": .ember
        case "optimize": .sage
        case "purge": .blue
        default: .violet
        }
    }

    private func color(_ command: String) -> Color { glow(command).color }
}
