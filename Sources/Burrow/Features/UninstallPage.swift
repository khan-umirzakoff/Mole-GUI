import SwiftUI

@MainActor
final class AppCatalog: ObservableObject {
    @Published var apps: [InstalledApp] = []
    @Published var sizes: [String: Int64] = [:]
    @Published var loading = false

    func load() async {
        loading = true
        defer { loading = false }
        apps = (try? await Mole.json([InstalledApp].self, ["uninstall", "--list"])) ?? []
        let paths = apps.map(\.path)
        for chunk in stride(from: 0, to: paths.count, by: 8).map({ Array(paths[$0..<min($0 + 8, paths.count)]) }) {
            let measured = await withTaskGroup(of: (String, Int64).self) { group in
                for p in chunk { group.addTask { (p, FolderSize.of(p)) } }
                var out: [(String, Int64)] = []
                for await r in group { out.append(r) }
                return out
            }
            for (p, s) in measured { sizes[p] = s }
        }
    }
}

enum FolderSize {
    /// Allocated size of a file or folder, without following symlinks.
    nonisolated static func of(_ path: String) -> Int64 {
        let url = URL(fileURLWithPath: path)
        let keys: Set<URLResourceKey> = [.totalFileAllocatedSizeKey, .isRegularFileKey]
        if let v = try? url.resourceValues(forKeys: keys), v.isRegularFile == true {
            return Int64(v.totalFileAllocatedSize ?? 0)
        }
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: Array(keys), options: [], errorHandler: { _, _ in true }) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            total += Int64((try? f.resourceValues(forKeys: keys))?.totalFileAllocatedSize ?? 0)
        }
        return total
    }
}

struct UninstallPage: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject var catalog: AppCatalog
    @ViewState private var query = ""
    @ViewState private var selected = Set<String>()
    @ViewState private var sortBySize = true
    @AppStorage("uninstall.withData") private var withData = false
    @AppStorage("uninstall.permanent") private var permanent = false
    @ViewState private var confirm: ConfirmAction?

    private var visible: [InstalledApp] {
        let list = catalog.apps.filter { query.isEmpty || $0.name.localizedCaseInsensitiveContains(query) }
        return sortBySize ? list.sorted { (catalog.sizes[$0.path] ?? 0) > (catalog.sizes[$1.path] ?? 0) }
                          : list.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var chosen: [InstalledApp] { catalog.apps.filter { selected.contains($0.path) } }
    private var chosenBytes: Int64 { chosen.map { catalog.sizes[$0.path] ?? 0 }.reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                SearchField(text: $query, prompt: "Search \(catalog.apps.count) apps")
                Picker("", selection: $sortBySize) {
                    Text("Largest").tag(true)
                    Text("A–Z").tag(false)
                }
                .pickerStyle(.segmented).frame(width: 160)
                CircleIconButton(symbol: "arrow.clockwise", help: "Reload") { Task { await catalog.load() } }
            }

            if catalog.apps.isEmpty {
                EmptyState(symbol: catalog.loading ? "hourglass" : "app.dashed",
                           text: catalog.loading ? "Finding your apps…" : "No apps found.")
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 14)], spacing: 14) {
                    ForEach(visible) { app in
                        AppTile(app: app, size: catalog.sizes[app.path], selected: selected.contains(app.path)) {
                            if selected.contains(app.path) { selected.remove(app.path) } else { selected.insert(app.path) }
                        }
                    }
                }
            }
        }
        .padding(.bottom, selected.isEmpty ? 0 : 90)
        .overlay(alignment: .bottom) {
            if !selected.isEmpty { actionBar.transition(.move(edge: .bottom).combined(with: .opacity)) }
        }
        .animation(.snappy, value: selected.isEmpty)
        .confirmation($confirm)
        .task { if catalog.apps.isEmpty { await catalog.load() } }
    }

    private var actionBar: some View {
        GlowCard(glow: .ember, style: .core, padding: 16) {
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(chosen.count) selected · \(chosenBytes.bytesText)").font(.system(size: 14, weight: .semibold))
                    Text(chosen.prefix(3).map(\.name).joined(separator: ", ") + (chosen.count > 3 ? "…" : "")).caption()
                }
                Spacer()
                Toggle("Personal data too", isOn: $withData).toggleStyle(.switch).controlSize(.small)
                Toggle("Skip Trash", isOn: $permanent).toggleStyle(.switch).controlSize(.small)
                Button("Preview") {
                    model.run("Preview uninstall", ["uninstall", "--dry-run"] + flags + names)
                }
                .buttonStyle(.pillSecondary)
                Button("Uninstall") { askToUninstall() }.buttonStyle(.pill)
            }
        }
        .frame(height: 76)
    }

    private var names: [String] { chosen.map(\.uninstall_name) }
    private var flags: [String] { (withData ? ["--with-data"] : []) + (permanent ? ["--permanent"] : []) }

    private func askToUninstall() {
        confirm = .init(title: "Uninstall \(chosen.count) app\(chosen.count == 1 ? "" : "s")?",
                        message: permanent ? "Apps and their leftovers are deleted for good." :
                            "Apps and their leftovers go to the Trash, so you can still restore them.",
                        button: "Uninstall") {
            model.run("Uninstalling", ["uninstall"] + flags + names) {
                selected.removeAll()
                Task { await catalog.load() }
            }
        }
    }
}

private struct AppTile: View {
    let app: InstalledApp
    let size: Int64?
    let selected: Bool
    let toggle: () -> Void
    @ViewState private var hover = false

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 12) {
                AppIcon(path: app.path, size: 40)
                VStack(alignment: .leading, spacing: 3) {
                    Text(app.name).font(.system(size: 13.5, weight: .medium)).lineLimit(1)
                    Text(size.map(\.bytesText) ?? "Measuring…").caption()
                }
                Spacer(minLength: 0)
                CheckDot(on: selected)
            }
            .padding(12)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(selected ? Glow.ember.color.opacity(0.22) : .white.opacity(hover ? 0.08 : 0.045)))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(selected ? Glow.ember.color.opacity(0.7) : Theme.hairline))
            .contentShape(RoundedRectangle(cornerRadius: 20))
        }
        .buttonStyle(.plain)
        .hoverLift(1.02)
        .onHover { hover = $0 }
        .contextMenu {
            Button("Show in Finder") { NSWorkspace.shared.selectFile(app.path, inFileViewerRootedAtPath: "") }
            if let id = app.bundle_id { Text(id) }
        }
    }
}

struct SearchField: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.secondaryText)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 38)
        .background(Capsule().fill(.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}
