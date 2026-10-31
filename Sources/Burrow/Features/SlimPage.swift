import SwiftUI

struct SlimPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scan: Scan<SlimReport>
    @ViewState private var selected = Set<String>()

    private var allSelected: Bool { !selected.isEmpty && selected.count == (scan.report?.apps.count ?? 0) }
    private var selectedBytes: Int64 { (scan.report?.apps ?? []).filter { selected.contains($0.name) }.map(\.bytes).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeroCard(glow: .magenta, label: "Intel code in universal apps", bytes: scan.report?.bytes,
                     detail: "Each app is slimmed on a copy that must pass code signing and Gatekeeper first. App updates bring the Intel code back.",
                     scanning: scan.scanning, progress: "Reading the architecture of every app",
                     started: scan.startedAt, checked: scan.finishedAt, error: scan.error) {
                ScanButton(scanning: scan.scanning, start: scan.start, stop: scan.cancel)
                Button(allSelected ? "Select none" : "Select all") {
                    selected = allSelected ? [] : Set((scan.report?.apps ?? []).map(\.name))
                }
                .buttonStyle(.pillSecondary)
                .disabled(scan.scanning || (scan.report?.apps ?? []).isEmpty)
            }

            if let apps = scan.report?.apps {
                if apps.isEmpty {
                    EmptyState(symbol: "checkmark.seal", text: "Every app is already Apple-silicon only.")
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 14)], spacing: 14) {
                        ForEach(apps) { app in
                            SelectTile(selected: selected.contains(app.name), glow: .magenta) {
                                if selected.contains(app.name) { selected.remove(app.name) } else { selected.insert(app.name) }
                            } content: {
                                AppIcon(path: appPath(app.name), size: 38)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(app.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                                    Text("\(app.bytes.bytesText) of Intel code").caption().lineLimit(1)
                                }
                            }
                        }
                    }
                    Text("Running apps are skipped, so quit them first. Mole shows the final list and waits for your confirmation.").caption()
                }
            } else if scan.error != nil, !scan.scanning {
                EmptyState(symbol: "exclamationmark.triangle", text: "The scan did not finish",
                           detail: scan.error ?? "", actionTitle: "Try again", action: scan.start)
            }
        }
        .bottomBar(!selected.isEmpty) {
            SelectionBar(glow: .magenta, title: "\(selected.count) app\(selected.count == 1 ? "" : "s") · \(selectedBytes.bytesText)",
                         subtitle: "Originals go to the Trash after the slim copy passes its checks.",
                         clear: { selected.removeAll() }) {
                Button("Slim apps") { slim() }.buttonStyle(.pill)
            }
        }
        .onAppear(perform: scan.startIfNeeded)
        .onChange(of: scan.scanning) { _, running in
            if !running { selected.formIntersection(Set((scan.report?.apps ?? []).map(\.name))) }
        }
    }

    private func appPath(_ name: String) -> String {
        let candidates = ["/Applications/\(name).app", "/Applications/\(name.replacingOccurrences(of: " ", with: "")).app",
                          ("~/Applications/\(name).app" as NSString).expandingTildeInPath]
        return candidates.first { FileManager.default.fileExists(atPath: $0) } ?? "/Applications"
    }

    private func slim() {
        let names = Array(selected)
        model.run("Slimming apps", ["slim"], plan: selectedBytes, responders: [.selectInMenu(titled: "Select apps to slim", names: names)]) {
            selected.removeAll()
            scan.start()
        }
    }
}
