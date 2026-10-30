import SwiftUI

struct InstallerFile: Identifiable, Hashable {
    var id: String { path }
    let path: String
    let bytes: Int64
    let modified: Date
    var name: String { (path as NSString).lastPathComponent }
    var folder: String { ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent }
}

/// Finds installer files in the same places Mole's `installer` command looks.
enum InstallerScanner {
    static let folders = [
        "~/Downloads", "~/Desktop", "~/Documents", "~/Library/Downloads", "/Users/Shared/Downloads",
        "~/Library/Mobile Documents/com~apple~CloudDocs/Downloads",
        "~/Library/Containers/com.apple.mail/Data/Library/Mail Downloads",
        "~/Library/Application Support/Telegram Desktop", "~/Downloads/Telegram Desktop",
    ].map { ($0 as NSString).expandingTildeInPath }

    static let kinds: Set<String> = ["dmg", "pkg", "mpkg", "iso", "xip"]

    nonisolated static func isInstaller(_ name: String) -> Bool {
        let ext = (name as NSString).pathExtension.lowercased()
        if kinds.contains(ext) { return true }
        // A zip counts only when its name says it carries an app or a setup.
        guard ext == "zip" else { return false }
        let lower = name.lowercased()
        return [".app.zip", "setup", "install", ".pkg.zip", ".dmg.zip"].contains { lower.contains($0) }
    }

    nonisolated static func scan() -> [InstallerFile] {
        var seen = Set<String>()
        var found: [InstallerFile] = []
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .contentModificationDateKey, .isRegularFileKey]
        for folder in folders {
            guard let e = FileManager.default.enumerator(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: keys,
                                                         options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { continue }
            for case let url as URL in e {
                if e.level > 2 { e.skipDescendants(); continue }
                guard isInstaller(url.lastPathComponent), seen.insert(url.path).inserted,
                      let v = try? url.resourceValues(forKeys: Set(keys)) else { continue }
                let bytes = v.isRegularFile == true ? Int64(v.totalFileAllocatedSize ?? 0) : FolderSize.of(url.path)
                found.append(.init(path: url.path, bytes: bytes, modified: v.contentModificationDate ?? .distantPast))
            }
        }
        return found.sorted { $0.bytes > $1.bytes }
    }
}

@MainActor
final class InstallerStore: ObservableObject {
    @Published var files: [InstallerFile]?
    @Published var scanning = false
    var onBusyChange: ((Bool) -> Void)?

    func load() async {
        guard !scanning else { return }
        scanning = true
        onBusyChange?(true)
        files = await Task.detached { InstallerScanner.scan() }.value
        scanning = false
        onBusyChange?(false)
    }
}

struct InstallersPage: View {
    @ObservedObject var store: InstallerStore
    @ViewState private var selected = Set<String>()
    @ViewState private var confirm: ConfirmAction?
    @ViewState private var failed: [String] = []

    private var files: [InstallerFile]? { store.files }
    private var total: Int64 { (files ?? []).map(\.bytes).reduce(0, +) }
    private var selectedBytes: Int64 { (files ?? []).filter { selected.contains($0.path) }.map(\.bytes).reduce(0, +) }
    private var allSelected: Bool { !selected.isEmpty && selected.count == (files?.count ?? 0) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeroCard(glow: .ember, label: "Installer files", bytes: files.map { _ in total },
                     detail: files.map { "\($0.count) disk image\($0.count == 1 ? "" : "s") and packages in Downloads, Desktop, Mail and Telegram." }
                        ?? "Looks in Downloads, Desktop, Documents, Mail and Telegram.",
                     scanning: store.scanning, progress: "Looking in Downloads, Desktop, Mail and Telegram") {
                Button("Rescan") { Task { await load() } }.buttonStyle(.pillSecondary).disabled(store.scanning)
                    .keyboardShortcut("r", modifiers: .command)
                Button(allSelected ? "Select none" : "Select all") {
                    selected = allSelected ? [] : Set((files ?? []).map(\.path))
                }
                .buttonStyle(.pillSecondary)
                .disabled((files ?? []).isEmpty)
            }

            if !failed.isEmpty {
                Label("\(failed.count) file\(failed.count == 1 ? "" : "s") could not be moved to the Trash: "
                      + failed.map { ($0 as NSString).lastPathComponent }.prefix(3).joined(separator: ", "),
                      systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.danger)
            }

            if let files, files.isEmpty {
                EmptyState(symbol: "checkmark.seal", text: "No installer files left behind.")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14)], spacing: 14) {
                ForEach(files ?? []) { file in
                    SelectTile(selected: selected.contains(file.path), glow: .ember) { toggle(file) } content: {
                        AppIcon(path: file.path, size: 38)
                        VStack(alignment: .leading, spacing: 3) {
                            Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1).truncationMode(.middle)
                            Text("\(file.folder) · \(file.modified.formatted(.relative(presentation: .named)))").caption().lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(file.bytes.bytesText).font(.system(size: 12, design: .monospaced))
                            .frame(width: 78, alignment: .trailing)
                    }
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "") }
                    }
                }
            }
        }
        .bottomBar(!selected.isEmpty) {
            SelectionBar(glow: .ember, title: "\(selected.count) file\(selected.count == 1 ? "" : "s") · \(selectedBytes.bytesText)",
                         subtitle: "They go to the Trash, so you can put them back.", clear: { selected.removeAll() }) {
                Button("Move to Trash") { askToTrash() }.buttonStyle(.pill)
            }
        }
        .confirmation($confirm)
        .onAppear { if store.files == nil { Task { await load() } } }
    }

    private func toggle(_ file: InstallerFile) {
        if selected.contains(file.path) { selected.remove(file.path) } else { selected.insert(file.path) }
    }

    private func load() async {
        await store.load()
        selected.formIntersection(Set((store.files ?? []).map(\.path)))
    }

    private func askToTrash() {
        confirm = .init(title: "Move \(selected.count) installer\(selected.count == 1 ? "" : "s") to the Trash?",
                        message: "\(selectedBytes.bytesText). You can restore them from the Trash.",
                        button: "Move to Trash") {
            failed = Trash.move(Array(selected))
            selected.removeAll()
            Task { await load() }
        }
    }
}
