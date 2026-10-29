import SwiftUI

struct ProjectsPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var scan: Scan<PurgeReport>
    @ViewState private var selected = Set<String>()
    @ViewState private var expanded = Set<String>()
    @ViewState private var confirm: ConfirmAction?
    @ViewState private var removing = false

    private var groups: [(project: String, artifacts: [PurgeReport.Artifact])] {
        let byProject = Dictionary(grouping: scan.report?.artifacts ?? [], by: \.project)
        return byProject.map { ($0.key, $0.value.sorted { $0.bytes > $1.bytes }) }
            .sorted { $0.1.map(\.bytes).reduce(0, +) > $1.1.map(\.bytes).reduce(0, +) }
    }

    private var selectedBytes: Int64 {
        (scan.report?.artifacts ?? []).filter { selected.contains($0.path) }.map(\.bytes).reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeroCard(glow: .blue, label: "Build folders found", bytes: scan.report?.bytes,
                     detail: "node_modules, .next, dist, target, .venv and other folders a reinstall or build brings back.",
                     scanning: scan.scanning || removing) {
                Button("Rescan") { Task { await rescan() } }.buttonStyle(.pillSecondary).disabled(scan.scanning)
                Button("Scan folders") { model.page = .settings }.buttonStyle(.pillSecondary)
            }

            if let report = scan.report, !report.artifacts.isEmpty {
                HStack {
                    Text("\(groups.count) projects · \(report.artifacts.count) folders").caption()
                    Spacer()
                    Button(selected.count == report.artifacts.count ? "Select none" : "Select all") {
                        selected = selected.count == report.artifacts.count ? [] : Set(report.artifacts.map(\.path))
                    }
                    .buttonStyle(.pillSecondary)
                }
                LazyVStack(spacing: 10) {
                    ForEach(groups, id: \.project) { group in projectRow(group.project, group.artifacts) }
                }
            } else if scan.report != nil {
                EmptyState(symbol: "shippingbox", text: "No build folders in your scan folders.")
            }
        }
        .padding(.bottom, selected.isEmpty ? 0 : 90)
        .overlay(alignment: .bottom) {
            if !selected.isEmpty {
                GlowCard(glow: .blue, style: .core, padding: 16) {
                    HStack {
                        Text("\(selected.count) folders · \(selectedBytes.bytesText)").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("Remove selected") { askToRemove() }.buttonStyle(.pill)
                    }
                }
                .frame(height: 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selected.isEmpty)
        .confirmation($confirm)
        .task { if scan.report == nil { await rescan() } }
    }

    private func projectRow(_ project: String, _ artifacts: [PurgeReport.Artifact]) -> some View {
        let paths = Set(artifacts.map(\.path))
        let all = paths.isSubset(of: selected)
        let total = artifacts.map(\.bytes).reduce(0, +)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Button { if all { selected.subtract(paths) } else { selected.formUnion(paths) } } label: { CheckDot(on: all) }
                    .buttonStyle(.plain)
                VStack(alignment: .leading, spacing: 2) {
                    Text((project as NSString).lastPathComponent).font(.system(size: 14, weight: .medium))
                    Text((project as NSString).abbreviatingWithTildeInPath).caption().lineLimit(1)
                }
                Spacer()
                ForEach(Array(Set(artifacts.map(\.kind))).sorted().prefix(3), id: \.self) { Tag(text: $0) }
                Text(total.bytesText).font(.system(size: 13, weight: .semibold, design: .monospaced)).frame(width: 90, alignment: .trailing)
                Button {
                    if expanded.contains(project) { expanded.remove(project) } else { expanded.insert(project) }
                } label: {
                    Image(systemName: expanded.contains(project) ? "chevron.up" : "chevron.down").frame(width: 24, height: 24)
                }
                .buttonStyle(.plain)
            }
            if expanded.contains(project) {
                ForEach(artifacts) { a in
                    HStack(spacing: 12) {
                        Button { if selected.contains(a.path) { selected.remove(a.path) } else { selected.insert(a.path) } } label: {
                            CheckDot(on: selected.contains(a.path))
                        }
                        .buttonStyle(.plain)
                        Text(a.path.replacingOccurrences(of: (project as NSString).abbreviatingWithTildeInPath + "/", with: ""))
                            .font(.system(size: 12.5, design: .monospaced)).foregroundStyle(Theme.secondaryText).lineLimit(1)
                        Spacer()
                        Text(a.bytes.bytesText).font(.system(size: 12, design: .monospaced))
                    }
                    .padding(.leading, 30)
                }
            }
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.white.opacity(all ? 0.09 : 0.045)))
        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).strokeBorder(all ? Glow.blue.color.opacity(0.6) : Theme.hairline))
    }

    private func rescan() async {
        await scan.run()
        selected.formIntersection(Set((scan.report?.artifacts ?? []).map(\.path)))
    }

    private func askToRemove() {
        let everything = selected.count == scan.report?.artifacts.count
        confirm = .init(title: "Remove \(selected.count) build folders?",
                        message: "\(selectedBytes.bytesText). They are deleted, not moved to the Trash; a reinstall or build recreates them.",
                        button: "Remove") {
            if everything {
                // Let Mole do the whole purge with its own safety checks.
                model.run("Removing build folders", ["purge", "--yes"]) { Task { await rescan() } }
            } else {
                removeSelected()
            }
        }
    }

    private func removeSelected() {
        let targets = (scan.report?.artifacts ?? []).filter { selected.contains($0.path) }.map(\.expandedPath)
        removing = true
        Task.detached {
            for path in targets { try? FileManager.default.removeItem(atPath: path) }
            await MainActor.run {
                removing = false
                selected.removeAll()
            }
            await rescan()
        }
    }
}
