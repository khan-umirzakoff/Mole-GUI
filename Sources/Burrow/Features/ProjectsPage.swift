import SwiftUI

struct ProjectsPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scan: Scan<PurgeReport>
    @ViewState private var selected = Set<String>()
    @ViewState private var expanded = Set<String>()
    @ViewState private var confirm: ConfirmAction?
    @ViewState private var removing = false
    @ViewState private var failed: [String] = []

    private var groups: [(project: String, artifacts: [PurgeReport.Artifact])] {
        let byProject = Dictionary(grouping: scan.current?.artifacts ?? [], by: \.project)
        return byProject.map { ($0.key, $0.value.sorted { $0.bytes > $1.bytes }) }
            .sorted { $0.1.map(\.bytes).reduce(0, +) > $1.1.map(\.bytes).reduce(0, +) }
    }

    private var selectedBytes: Int64 {
        (scan.report?.artifacts ?? []).filter { selected.contains($0.path) }.map(\.bytes).reduce(0, +)
    }

    var body: some View {
        let report = scan.current
        VStack(alignment: .leading, spacing: 20) {
            HeroCard(glow: .blue, label: scan.scanning ? "Found so far" : "Build folders found", bytes: report?.bytes,
                     detail: "node_modules, .next, dist, target, .venv and other folders a reinstall or build brings back.",
                     scanning: scan.scanning || removing,
                     progress: removing ? "Moving folders to the Trash…" : scan.status.isEmpty ? "" : "Looking in \(scan.status)",
                     started: scan.startedAt, error: scan.error) {
                ScanButton(scanning: scan.scanning, start: rescan, stop: scan.cancel).disabled(removing)
                Button { model.page = .settings } label: { Label("Scan folders", systemImage: "folder.badge.gearshape") }
                    .buttonStyle(.pillSecondary)
            }

            if let report, !report.notes.isEmpty {
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Notes(notes: report.notes)
                    if report.skippedRoots.contains(where: ConfigList.isHome) {
                        Button("Change scan folders") { model.page = .settings }
                            .buttonStyle(.plain).font(.system(size: 12.5, weight: .medium)).foregroundStyle(Glow.blue.color)
                            .help("Your whole home folder is a scan folder; it is too large to finish")
                    }
                }
            }
            if !failed.isEmpty {
                Label("\(failed.count) folder\(failed.count == 1 ? "" : "s") could not be moved to the Trash", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.danger)
                    .help(failed.joined(separator: "\n"))
            }

            if let report, !report.artifacts.isEmpty {
                HStack {
                    Text("\(groups.count) projects · \(report.artifacts.count) folders").caption()
                    Spacer()
                    if !scan.scanning {
                        Button(selected.count == report.artifacts.count ? "Select none" : "Select all") {
                            selected = selected.count == report.artifacts.count ? [] : Set(report.artifacts.map(\.path))
                        }
                        .buttonStyle(.pillSecondary)
                    }
                }
                LazyVStack(spacing: 10) {
                    ForEach(groups, id: \.project) { group in projectRow(group.project, group.artifacts) }
                }
                .animation(Motion.spring, value: groups.count)
            } else if scan.report != nil, !scan.scanning {
                EmptyState(symbol: "shippingbox", text: "No build folders in your scan folders.",
                           detail: "Projects looks in the folders listed in Settings.", actionTitle: "Scan folders") { model.page = .settings }
            } else if scan.error != nil, !scan.scanning {
                EmptyState(symbol: "exclamationmark.triangle", text: "The scan did not finish",
                           detail: scan.error ?? "", actionTitle: "Try again", action: rescan)
            }
        }
        .bottomBar(!selected.isEmpty && !scan.scanning) {
            SelectionBar(glow: .blue, title: "\(selected.count) folder\(selected.count == 1 ? "" : "s") · \(selectedBytes.bytesText)",
                         subtitle: everythingSelected ? "Mole removes them; a reinstall or build brings them back."
                                                      : "They go to the Trash; a reinstall or build brings them back.",
                         clear: { selected.removeAll() }) {
                Button("Remove selected") { askToRemove() }.buttonStyle(.pill).disabled(removing)
            }
        }
        .confirmation($confirm)
        .onAppear(perform: scan.startIfNeeded)
        .onChange(of: scan.scanning) { _, running in
            if !running { selected.formIntersection(Set((scan.report?.artifacts ?? []).map(\.path))) }
        }
    }

    private func projectRow(_ project: String, _ artifacts: [PurgeReport.Artifact]) -> some View {
        let paths = Set(artifacts.map(\.path))
        let all = paths.isSubset(of: selected)
        let total = artifacts.map(\.bytes).reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { if all { selected.subtract(paths) } else { selected.formUnion(paths) } } label: { CheckDot(on: all) }
                    .buttonStyle(.plain)
                    .disabled(scan.scanning)
                    .accessibilityLabel("Select every build folder in \((project as NSString).lastPathComponent)")
                    .accessibilityAddTraits(all ? .isSelected : [])
                VStack(alignment: .leading, spacing: 2) {
                    Text((project as NSString).lastPathComponent).font(.system(size: 14, weight: .medium))
                    Text((project as NSString).abbreviatingWithTildeInPath).caption().lineLimit(1)
                }
                Spacer()
                ForEach(Array(Set(artifacts.map(\.kind))).sorted().prefix(3), id: \.self) { Tag(text: $0) }
                Text(total.bytesText).font(.system(size: 13, weight: .semibold)).monospacedDigit().frame(width: 90, alignment: .trailing)
                Image(systemName: "chevron.down")
                    .rotationEffect(.degrees(expanded.contains(project) ? 180 : 0))
                    .frame(width: 24, height: 24)
                    .accessibilityHidden(true)
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleExpanded(project) }
            .accessibilityAction(named: expanded.contains(project) ? "Collapse" : "Expand") { toggleExpanded(project) }
            if expanded.contains(project) {
                ForEach(artifacts) { a in
                    HStack(spacing: 12) {
                        Button { if selected.contains(a.path) { selected.remove(a.path) } else { selected.insert(a.path) } } label: {
                            CheckDot(on: selected.contains(a.path))
                        }
                        .buttonStyle(.plain)
                        .disabled(scan.scanning)
                        .accessibilityLabel("Select \(a.kind)")
                        .accessibilityAddTraits(selected.contains(a.path) ? .isSelected : [])
                        Text(a.path.replacingOccurrences(of: (project as NSString).abbreviatingWithTildeInPath + "/", with: ""))
                            .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        Spacer()
                        Text(a.bytes.bytesText).font(.system(size: 12)).monospacedDigit()
                    }
                    .padding(.leading, 30)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.selectFile(a.expandedPath, inFileViewerRootedAtPath: "") }
                    }
                }
            }
        }
        .clipped()
        .animation(Motion.spring, value: expanded.contains(project))
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(all ? 0.09 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(all ? Glow.blue.color.opacity(0.6) : Theme.hairline))
    }

    private var everythingSelected: Bool { selected.count == scan.report?.artifacts.count }

    private func toggleExpanded(_ project: String) {
        if expanded.contains(project) { expanded.remove(project) } else { expanded.insert(project) }
    }

    private func rescan() {
        failed = []
        scan.start()
    }

    private func askToRemove() {
        if everythingSelected {
            confirm = .init(title: "Remove all \(selected.count) build folders?",
                            message: "\(selectedBytes.bytesText). Mole deletes them with its own safety checks and shows its final count before it starts.",
                            button: "Continue") {
                // Mole's selector opens with exactly these folders ticked (recent ones stay off);
                // Enter accepts it, then Mole asks for the final confirmation in the sheet.
                model.run("Removing build folders", ["purge"],
                          responders: [.when("Select Artifacts to Purge", send: "\r")]) { rescan() }
            }
        } else {
            confirm = .init(title: "Move \(selected.count) build folder\(selected.count == 1 ? "" : "s") to the Trash?",
                            message: "\(selectedBytes.bytesText). You can restore them from the Trash; a reinstall or build also recreates them.",
                            button: "Move to Trash") { trashSelected() }
        }
    }

    /// Only folders Mole listed, inside the home folder, are touched.
    private func trashSelected() {
        let home = FileManager.default.homeDirectoryForCurrentUser.path + "/"
        let targets = (scan.report?.artifacts ?? []).filter { selected.contains($0.path) }.map(\.expandedPath)
            .filter { $0.hasPrefix(home) }
        removing = true
        Task {
            let failures = await Task.detached { Trash.move(targets) }.value
            removing = false
            failed = failures
            selected.removeAll()
            // Drop what is gone instead of a minutes-long rescan.
            let gone = Set(targets).subtracting(failures)
            scan.update { $0.artifacts.removeAll { gone.contains($0.expandedPath) } }
        }
    }
}
