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

    func load() async {
        guard !scanning else { return }
        scanning = true
        files = await Task.detached { InstallerScanner.scan() }.value
        scanning = false
    }
}

struct InstallersPage: View {
    @ObservedObject var store: InstallerStore
    @ViewState private var selected = Set<String>()
    @ViewState private var confirm: ConfirmAction?

    private var total: Int64 { (files ?? []).map(\.bytes).reduce(0, +) }
    private var selectedBytes: Int64 { (files ?? []).filter { selected.contains($0.path) }.map(\.bytes).reduce(0, +) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeroCard(glow: .ember, label: "Installer files", bytes: files.map { _ in total },
                     detail: "\(files?.count ?? 0) disk images and packages in Downloads, Desktop, Mail and Telegram.",
                     scanning: store.scanning) {
                Button("Rescan") { Task { await load() } }.buttonStyle(.pillSecondary)
                Button(selected.count == (files?.count ?? 0) && !selected.isEmpty ? "Select none" : "Select all") {
                    selected = selected.count == files?.count ? [] : Set((files ?? []).map(\.path))
                }
                .buttonStyle(.pillSecondary)
            }

            if let files, files.isEmpty {
                EmptyState(symbol: "opticaldiscdrive", text: "No installer files left behind.")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 14)], spacing: 14) {
                ForEach(files ?? []) { file in
                    Button { toggle(file) } label: {
                        HStack(spacing: 12) {
                            AppIcon(path: file.path, size: 38)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(file.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                                Text("\(file.folder) · \(file.modified.formatted(.relative(presentation: .named)))").caption().lineLimit(1)
                            }
                            Spacer(minLength: 0)
                            Text(file.bytes.bytesText).font(.system(size: 12, design: .monospaced))
                            CheckDot(on: selected.contains(file.path))
                        }
                        .padding(12)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .fill(selected.contains(file.path) ? Glow.ember.color.opacity(0.2) : .white.opacity(0.045)))
                        .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .strokeBorder(selected.contains(file.path) ? Glow.ember.color.opacity(0.7) : Theme.hairline))
                        .contentShape(RoundedRectangle(cornerRadius: 20))
                    }
                    .buttonStyle(.plain)
                    .hoverLift(1.02)
                    .contextMenu {
                        Button("Show in Finder") { NSWorkspace.shared.selectFile(file.path, inFileViewerRootedAtPath: "") }
                    }
                }
            }
        }
        .padding(.bottom, selected.isEmpty ? 0 : 90)
        .overlay(alignment: .bottom) {
            if !selected.isEmpty {
                GlowCard(glow: .ember, style: .core, padding: 16) {
                    HStack {
                        Text("\(selected.count) files · \(selectedBytes.bytesText)").font(.system(size: 14, weight: .semibold))
                        Spacer()
                        Button("Move to Trash") { askToTrash() }.buttonStyle(.pill)
                    }
                }
                .frame(height: 70)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.snappy, value: selected.isEmpty)
        .confirmation($confirm)
        .task { if files == nil { await load() } }
    }

    private func toggle(_ file: InstallerFile) {
        if selected.contains(file.path) { selected.remove(file.path) } else { selected.insert(file.path) }
    }

    private var files: [InstallerFile]? { store.files }

    private func load() async {
        await store.load()
        selected.formIntersection(Set((store.files ?? []).map(\.path)))
    }

    private func askToTrash() {
        confirm = .init(title: "Move \(selected.count) installers to the Trash?",
                        message: "\(selectedBytes.bytesText). You can restore them from the Trash.",
                        button: "Move to Trash") {
            for path in selected { try? FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil) }
            selected.removeAll()
            Task { await load() }
        }
    }
}
