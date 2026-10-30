import SwiftUI

/// What apps that are gone left in ~/Library: folders and files named after their bundle id.
struct Leftover: Identifiable, Hashable {
    enum Kind: String { case cache = "Cache", logs = "Logs", state = "Window state", web = "Web data", data = "App data", settings = "Settings" }
    struct Item: Hashable { let path: String; let kind: Kind; let bytes: Int64 }

    var id: String { bundleID }
    let bundleID: String
    let items: [Item]
    let lastUsed: Date
    /// The app itself, when it still sits in the Trash.
    var trashedApp: String?

    var bytes: Int64 { items.map(\.bytes).reduce(0, +) }
    var kinds: [Kind] { Array(Set(items.map(\.kind))).sorted { $0.rawValue < $1.rawValue } }
    var name: String {
        if let trashedApp { return ((trashedApp as NSString).lastPathComponent as NSString).deletingPathExtension }
        let last = bundleID.split(separator: ".").last.map(String.init) ?? bundleID
        return last.prefix(1).uppercased() + last.dropFirst()
    }
}

/// Finds leftovers the way Mole's `clean` does (bundle-id names, never Apple's or a password
/// manager's), but caches show after a week unused instead of Mole's 30 days. Anything touched
/// in the last week still has a user (often a command-line tool); app data and settings wait
/// 30 days. A vendor with any app still installed keeps all its folders: updaters and helpers
/// share the vendor's prefix.
enum LeftoverScanner {
    static let places: [(String, Leftover.Kind)] = [
        ("Library/Caches", .cache), ("Library/Logs", .logs), ("Library/Saved Application State", .state),
        ("Library/HTTPStorages", .web), ("Library/WebKit", .web),
        ("Library/Application Support", .data), ("Library/Preferences", .settings),
    ]
    static let prefixes: Set<String> = ["com", "org", "net", "io", "app", "dev", "ai", "co", "me"]
    /// Mole's never-delete patterns, plus system parts that are not apps (printing).
    static let never = ["password", "keychain", "bitwarden", "lastpass", "keepass", "dashlane", "enpass",
                        "ssh", "gpg", "gnupg", "org.cups."]
    static let cacheAge: TimeInterval = 7 * 86400
    static let dataAge: TimeInterval = 30 * 86400

    /// "com.foo.Bar", "com.foo.Bar.savedState", "com.foo.Bar.plist" → "com.foo.Bar".
    nonisolated static func bundleID(fromEntry name: String) -> String? {
        var id = name
        for ext in [".savedState", ".plist", ".binarycookies"] where id.hasSuffix(ext) { id = String(id.dropLast(ext.count)) }
        let parts = id.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count >= 3, parts.allSatisfy({ !$0.isEmpty }), prefixes.contains(parts[0].lowercased()),
              id.allSatisfy({ $0.isLetter || $0.isNumber || "-_.".contains($0) }) else { return nil }
        return id
    }

    /// Whether `id` may still belong to something on this Mac. `installed` is lowercased.
    nonisolated static func inUse(_ id: String, installed: Set<String>) -> Bool {
        let lower = id.lowercased()
        if lower.hasPrefix("com.apple.") || never.contains(where: lower.contains) { return true }
        let vendor = lower.split(separator: ".").prefix(2).joined(separator: ".") + "."
        return installed.contains { $0 == lower || $0.hasPrefix(vendor) }
    }

    nonisolated static func scan() -> [Leftover] {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser
        let installed = installedIDs()
        let protected = ConfigList.whitelist.read().map { ($0 as NSString).expandingTildeInPath }
        let trashed = trashedApps()
        var found: [String: [Leftover.Item]] = [:]
        var used: [String: Date] = [:]
        for (place, kind) in places {
            let dir = home.appendingPathComponent(place)
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            for name in names {
                guard let id = bundleID(fromEntry: name), !inUse(id, installed: installed) else { continue }
                let path = dir.appendingPathComponent(name).path
                guard !protected.contains(where: { fnmatch($0, path, 0) == 0 || path.hasPrefix($0 + "/") }) else { continue }
                let modified = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
                let age = kind == .data || kind == .settings ? dataAge : cacheAge
                if Date().timeIntervalSince(modified) < age { continue }
                found[id, default: []].append(.init(path: path, kind: kind, bytes: FolderSize.of(path)))
                used[id] = max(used[id] ?? .distantPast, modified)
            }
        }
        // A last check with LaunchServices catches apps outside the usual folders.
        return found.compactMap { id, items in
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id),
               !url.path.contains("/.Trash/"), fm.fileExists(atPath: url.path) { return nil }
            return Leftover(bundleID: id, items: items.sorted { $0.bytes > $1.bytes }, lastUsed: used[id] ?? .distantPast,
                            trashedApp: trashed[id.lowercased()])
        }
        .sorted { $0.bytes > $1.bytes }
    }

    /// Bundle ids of every app in the usual places and every running one, lowercased.
    nonisolated static func installedIDs() -> Set<String> {
        let fm = FileManager.default
        var ids = Set(NSWorkspace.shared.runningApplications.compactMap { $0.bundleIdentifier?.lowercased() })
        let roots = ["/Applications", "/System/Applications", "/Library/Application Support",
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Applications").path,
                     fm.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support").path]
        for root in roots {
            guard let e = fm.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: nil,
                                        options: [.skipsHiddenFiles, .skipsPackageDescendants], errorHandler: { _, _ in true }) else { continue }
            for case let url as URL in e {
                if e.level > 4 { e.skipDescendants(); continue }
                guard url.pathExtension == "app" else { continue }
                if let id = Bundle(url: url)?.bundleIdentifier { ids.insert(id.lowercased()) }
            }
        }
        return ids
    }

    /// Apps waiting in the Trash, by bundle id (lowercased): their name and icon still help.
    /// Reading the Trash needs Full Disk Access; without it the list is empty.
    nonisolated static func trashedApps() -> [String: String] {
        let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
        let names = (try? FileManager.default.contentsOfDirectory(atPath: trash.path)) ?? []
        var out: [String: String] = [:]
        for name in names where name.hasSuffix(".app") {
            let path = trash.appendingPathComponent(name).path
            if let id = Bundle(path: path)?.bundleIdentifier { out[id.lowercased()] = path }
        }
        return out
    }
}

@MainActor
final class LeftoverStore: ObservableObject {
    @Published var leftovers: [Leftover]?
    @Published var scanning = false
    var onBusyChange: ((Bool) -> Void)?

    func load() async {
        guard !scanning else { return }
        scanning = true
        onBusyChange?(true)
        leftovers = await Task.detached { LeftoverScanner.scan() }.value
        scanning = false
        onBusyChange?(false)
    }

    /// Moves what is still a leftover to the Trash, after checking again that its app is gone.
    /// Returns the paths that could not be moved.
    func trash(_ chosen: [Leftover]) async -> [String] {
        let failed = await Task.detached {
            let installed = LeftoverScanner.installedIDs()
            let paths = chosen.filter { !LeftoverScanner.inUse($0.bundleID, installed: installed) }
                .flatMap(\.items).map(\.path).filter { FileManager.default.fileExists(atPath: $0) }
            return Trash.move(paths)
        }.value
        await load()
        return failed
    }
}

struct LeftoversView: View {
    @ObservedObject var store: LeftoverStore
    @ViewState private var selected = Set<String>()
    @ViewState private var confirm: ConfirmAction?
    @ViewState private var failed: [String] = []

    private var all: [Leftover] { store.leftovers ?? [] }
    private var chosen: [Leftover] { all.filter { selected.contains($0.id) } }
    private var allSelected: Bool { !selected.isEmpty && selected.count == all.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HeroCard(glow: .ember, label: "Leftovers of removed apps", bytes: store.leftovers.map { $0.map(\.bytes).reduce(0, +) },
                     detail: store.leftovers.map { "\($0.count) app\($0.count == 1 ? "" : "s") that are gone left caches, logs or settings behind." }
                        ?? "Looks through your Library for what removed apps left.",
                     scanning: store.scanning, progress: "Looking through your Library") {
                Button("Rescan") { Task { await store.load() } }.buttonStyle(.pillSecondary).disabled(store.scanning)
                    .keyboardShortcut("r", modifiers: .command)
                Button(allSelected ? "Select none" : "Select all") {
                    selected = allSelected ? [] : Set(all.map(\.id))
                }
                .buttonStyle(.pillSecondary)
                .disabled(all.isEmpty)
            }

            if !failed.isEmpty {
                Label("\(failed.count) item\(failed.count == 1 ? "" : "s") could not be moved to the Trash.", systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 12.5)).foregroundStyle(Theme.danger)
            }

            if let leftovers = store.leftovers, leftovers.isEmpty {
                EmptyState(symbol: "checkmark.seal", text: "No leftovers of removed apps.")
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 360), spacing: 14)], spacing: 14) {
                ForEach(all) { left in
                    SelectTile(selected: selected.contains(left.id), glow: .ember) { toggle(left) } content: {
                        if let app = left.trashedApp {
                            AppIcon(path: app, size: 38)
                        } else {
                            Image(systemName: "app.dashed").font(.system(size: 22, weight: .light))
                                .frame(width: 38, height: 38).foregroundStyle(Theme.secondaryText)
                        }
                        VStack(alignment: .leading, spacing: 3) {
                            Text(left.name).font(.system(size: 13, weight: .medium)).lineLimit(1)
                            Text("\(left.kinds.map(\.rawValue).joined(separator: ", ")) · used \(left.lastUsed.formatted(.relative(presentation: .named)))")
                                .caption().lineLimit(1)
                        }
                        Spacer(minLength: 8)
                        Text(left.bytes.bytesText).font(.system(size: 12)).monospacedDigit()
                            .frame(width: 78, alignment: .trailing)
                    }
                    .help(left.bundleID)
                    .contextMenu {
                        Text(left.bundleID)
                        ForEach(left.items, id: \.path) { item in
                            Button("Show \(item.kind.rawValue.lowercased()) in Finder") {
                                NSWorkspace.shared.selectFile(item.path, inFileViewerRootedAtPath: "")
                            }
                        }
                    }
                }
            }
            Text("Folders and files named after apps that are no longer on this Mac, unused for a week (settings and app data: 30 days). Some belong to tools without an app; their caches are safe to remove. Everything goes to the Trash.").caption()
        }
        .bottomBar(!selected.isEmpty) {
            SelectionBar(glow: .ember, title: "\(chosen.count) app\(chosen.count == 1 ? "" : "s") · \(chosen.map(\.bytes).reduce(0, +).bytesText)",
                         subtitle: "Their leftovers go to the Trash, so you can put them back.", clear: { selected.removeAll() }) {
                Button("Move to Trash") { askToTrash() }.buttonStyle(.pill)
            }
        }
        .confirmation($confirm)
        .onAppear { if store.leftovers == nil { Task { await store.load() } } }
    }

    private func toggle(_ left: Leftover) {
        if selected.contains(left.id) { selected.remove(left.id) } else { selected.insert(left.id) }
    }

    private func askToTrash() {
        let items = chosen.flatMap(\.items).count
        confirm = .init(title: "Move what \(chosen.count) removed app\(chosen.count == 1 ? "" : "s") left to the Trash?",
                        message: "\(items) item\(items == 1 ? "" : "s"), \(chosen.map(\.bytes).reduce(0, +).bytesText). You can restore them from the Trash.",
                        button: "Move to Trash") {
            let picked = chosen
            selected.removeAll()
            Task {
                failed = await store.trash(picked)
                selected.formIntersection(Set(all.map(\.id)))
            }
        }
    }
}
