import SwiftUI

/// A line-based Mole config file (`whitelist`, `purge_paths`): comments are kept as they are.
struct ConfigList {
    let url: URL

    static let whitelist = ConfigList(url: home(".config/mole/whitelist"))
    static let purgePaths = ConfigList(url: home(".config/mole/purge_paths"))

    static func home(_ path: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(path)
    }

    func read() -> [String] {
        ((try? String(contentsOf: url, encoding: .utf8)) ?? "")
            .split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    func write(_ entries: [String]) {
        let text = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
        let comments = text.split(separator: "\n", omittingEmptySubsequences: false).filter { $0.hasPrefix("#") }
        let body = (comments.map(String.init) + (comments.isEmpty ? [] : [""]) + entries).joined(separator: "\n") + "\n"
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? body.write(to: url, atomically: true, encoding: .utf8)
    }
}

struct SettingsPage: View {
    @EnvironmentObject private var model: AppModel
    @ViewState private var whitelist: [String] = []
    @ViewState private var purgePaths: [String] = []
    /// nil while checking.
    @ViewState private var touchID: Bool?
    @ViewState private var confirm: ConfirmAction?

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 18) {
                PathListCard(title: "Protected paths",
                             caption: "Clean, Optimize and Slim never touch these. Wildcards like * work.",
                             glow: .sage, entries: $whitelist) { ConfigList.whitelist.write($0) }
                PathListCard(title: "Project scan folders",
                             caption: "Where Projects looks for build folders.",
                             warning: purgePaths.contains { ["~", "~/", NSHomeDirectory()].contains($0) }
                                ? "Your whole home folder is slow to scan and can time out. Project folders work best." : "",
                             glow: .blue, entries: $purgePaths) { ConfigList.purgePaths.write($0) }
            }

            HStack(alignment: .top, spacing: 18) {
                GlowCard(glow: .violet, style: .core) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Touch ID for admin steps", systemImage: "touchid").cardTitle()
                            Spacer()
                            switch touchID {
                            case true?: Tag(text: "On", color: Theme.accent)
                            case false?: Tag(text: "Off")
                            case nil: PulseDot(color: .white)
                            }
                        }
                        Text("Approve Mole's administrator steps with your fingerprint instead of typing the password. Changing it asks for your password once.").caption()
                        Spacer(minLength: 0)
                        if let on = touchID {
                            Button(on ? "Turn off" : "Turn on") {
                                model.run("Touch ID for sudo", ["touchid", on ? "disable" : "enable"]) { Task { await checkTouchID() } }
                            }
                            .buttonStyle(on ? .pillSecondary : .pill)
                        }
                    }
                }
                .frame(height: 210)

                GlowCard(glow: .graphite, style: .plain) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("About").cardTitle()
                        Text("Burrow is a free, open-source window for Mole \(Mole.version), the macOS cleaner by tw93. Every change goes through Mole itself, with its safety checks and protection rules.").caption()
                        Text("Licensed GPL-3.0, like Mole.").caption()
                        Spacer(minLength: 0)
                        HStack {
                            Link("Mole on GitHub", destination: URL(string: "https://github.com/tw93/Mole")!)
                                .buttonStyle(.pillSecondary)
                            Button("Mole's logs") {
                                NSWorkspace.shared.open(ConfigList.home("Library/Logs/mole"))
                            }
                            .buttonStyle(.pillSecondary)
                        }
                    }
                }
                .frame(height: 210)
            }

            GlowCard(glow: .ember, style: .rim, padding: 22) {
                HStack {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Remove Burrow completely").cardTitle()
                        Text("Moves the app to the Trash and deletes everything it and Mole keep on this Mac: ~/.config/mole, ~/.cache/mole, ~/Library/Logs/mole and the app's preferences.").caption()
                    }
                    Spacer()
                    Button("Remove…") { askToRemoveApp() }.buttonStyle(.pillDanger)
                }
            }
            .frame(height: 120)
        }
        .confirmation($confirm)
        .task {
            whitelist = ConfigList.whitelist.read()
            purgePaths = ConfigList.purgePaths.read()
            await checkTouchID()
        }
    }

    private func checkTouchID() async {
        touchID = nil
        let out = String(decoding: (try? await Mole.capture(["touchid", "status"])) ?? Data(), as: UTF8.self)
        touchID = out.contains("is enabled")
    }

    private func askToRemoveApp() {
        confirm = .init(title: "Remove Burrow and all its data?",
                        message: "Mole's protection rules, scan folders, history and logs are deleted too. Files Mole already moved to the Trash stay there.",
                        button: "Remove") {
            Uninstaller.removeEverything()
        }
    }
}

enum Uninstaller {
    /// Deletes Mole's state and the app's own preferences, then trashes the bundle and quits.
    static func removeEverything() {
        let fm = FileManager.default
        for path in [".config/mole", ".cache/mole", "Library/Logs/mole",
                     "Library/Saved Application State/\(Bundle.main.bundleIdentifier ?? "uz.khan.burrow").savedState"] {
            try? fm.removeItem(at: ConfigList.home(path))
        }
        if let id = Bundle.main.bundleIdentifier {
            UserDefaults.standard.removePersistentDomain(forName: id)
            try? fm.removeItem(at: ConfigList.home("Library/Preferences/\(id).plist"))
            try? fm.removeItem(at: ConfigList.home("Library/Caches/\(id)"))
            try? fm.removeItem(at: ConfigList.home("Library/HTTPStorages/\(id)"))
        }
        if Bundle.main.bundleURL.pathExtension == "app" {
            try? fm.trashItem(at: Bundle.main.bundleURL, resultingItemURL: nil)
        }
        NSApp.terminate(nil)
    }
}

private struct PathListCard: View {
    let title: String
    let caption: String
    var warning = ""
    let glow: Glow
    @Binding var entries: [String]
    let save: ([String]) -> Void
    @ViewState private var draft = ""

    var body: some View {
        GlowCard(glow: glow, style: .plain) {
            VStack(alignment: .leading, spacing: 12) {
                Text(title).cardTitle()
                Text(caption).caption()
                if !warning.isEmpty {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11.5)).foregroundStyle(.orange)
                }
                VStack(spacing: 6) {
                    if entries.isEmpty {
                        Text("None yet").font(.system(size: 12)).foregroundStyle(Theme.tertiaryText)
                            .frame(maxWidth: .infinity, alignment: .leading).padding(.leading, 12).frame(height: 30)
                    }
                    ForEach(entries, id: \.self) { entry in
                        HStack {
                            Text((entry as NSString).abbreviatingWithTildeInPath)
                                .font(.system(size: 12, design: .monospaced)).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Button {
                                withAnimation(Motion.quick) { entries.removeAll { $0 == entry } }
                                save(entries)
                            } label: {
                                Image(systemName: "minus.circle.fill").frame(width: 24, height: 24).contentShape(Rectangle())
                            }
                            .buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
                            .help("Remove")
                            .accessibilityLabel("Remove \(entry)")
                        }
                        .padding(.leading, 12).padding(.trailing, 4).frame(height: 30)
                        .background(Capsule().fill(.white.opacity(0.05)))
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                }
                HStack {
                    TextField("Add a path", text: $draft)
                        .textFieldStyle(.plain).padding(.horizontal, 12).frame(height: 32)
                        .background(Capsule().fill(.white.opacity(0.07)))
                        .onSubmit(add)
                    CircleIconButton(symbol: "folder.badge.plus", help: "Choose a folder") { choose() }
                }
            }
        }
    }

    private func add() {
        let path = draft.trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty, !entries.contains(path) else { return }
        withAnimation(Motion.quick) { entries.append(path) }
        save(entries)
        draft = ""
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            draft = url.path
            add()
        }
    }
}
