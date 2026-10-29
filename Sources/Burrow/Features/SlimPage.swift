import SwiftUI

struct SlimPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scan: Scan<SlimReport>
    @ViewState private var selected = Set<String>()

    private var selectedBytes: Int64 { (scan.report?.apps ?? []).filter { selected.contains($0.name) }.map(\.bytes).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeroCard(glow: .magenta, label: "Intel code in universal apps", bytes: scan.report?.bytes,
                     detail: "Each app is slimmed on a copy that must pass code signing and Gatekeeper first. App updates bring the Intel code back.",
                     scanning: scan.scanning) {
                Button("Rescan") { Task { await scan.run() } }.buttonStyle(.pillSecondary).disabled(scan.scanning)
            }

            if let apps = scan.report?.apps {
                if apps.isEmpty { EmptyState(symbol: "scissors", text: "Every app is already Apple-silicon only.") }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                    ForEach(apps) { app in
                        Button {
                            if selected.contains(app.name) { selected.remove(app.name) } else { selected.insert(app.name) }
                        } label: {
                            HStack(spacing: 12) {
                                AppIcon(path: appPath(app.name), size: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                                    Text("\(app.bytes.bytesText) of Intel code").caption()
                                }
                                Spacer(minLength: 0)
                                CheckDot(on: selected.contains(app.name))
                            }
                            .padding(12)
                            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .fill(selected.contains(app.name) ? Glow.magenta.color.opacity(0.2) : .white.opacity(0.045)))
                            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                                .strokeBorder(selected.contains(app.name) ? Glow.magenta.color.opacity(0.7) : Theme.hairline))
                            .contentShape(RoundedRectangle(cornerRadius: 20))
                        }
                        .buttonStyle(.plain)
                        .hoverLift(1.02)
                    }
                }
                Text("Running apps are skipped. Quit them first. Mole shows the final list and waits for your confirmation.").caption()
            }
        }
        .padding(.bottom, selected.isEmpty ? 0 : 90)
        .overlay(alignment: .bottom) {
            if !selected.isEmpty {
                GlowCard(glow: .magenta, style: .core, padding: 16) {
                    HStack {
                        Text("\(selected.count) apps · \(selectedBytes.bytesText)").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("Slim apps") { slim() }.buttonStyle(.pill)
                    }
                }
                .frame(height: 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selected.isEmpty)
        .task { if scan.report == nil { await scan.run() } }
    }

    private func appPath(_ name: String) -> String {
        let candidates = ["/Applications/\(name).app", "/Applications/\(name.replacingOccurrences(of: " ", with: "")).app",
                          ("~/Applications/\(name).app" as NSString).expandingTildeInPath]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "/Applications"
    }

    private func slim() {
        let names = Array(selected)
        model.run("Slimming apps", ["slim"], responders: [.selectInMenu(titled: "Select apps to slim", names: names)]) {
            selected.removeAll()
            Task { await scan.run() }
        }
    }
}
