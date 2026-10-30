import SwiftUI

@main
struct BurrowApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Burrow") {
            RootView()
                .environmentObject(model)
                .onAppear {
                    delegate.model = model
                    if let folder = UserDefaults.standard.string(forKey: "tour") { Tour.start(model, into: folder) }
                }
                .frame(minWidth: 1080, minHeight: 700)
                .preferredColorScheme(.dark)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1280, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandMenu("Go") {
                ForEach(Page.allCases) { page in
                    Button(page.title) { model.page = page }
                        .keyboardShortcut(page.shortcut, modifiers: .command)
                }
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var signalSources: [DispatchSourceSignal] = []
    /// Set by the app once its model exists, so quitting can see a running session.
    weak var model: AppModel?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from `swift run` the binary is not an app bundle yet; make it a normal app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
        // `kill` or a logout skips applicationWillTerminate; stop Mole's processes then too.
        for sig in [SIGTERM, SIGHUP, SIGINT] {
            // A do-nothing handler, not SIG_IGN: an ignored signal is inherited by every Mole
            // process Burrow starts, while a handled one is reset to the default on exec.
            signal(sig) { _ in }
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                Mole.terminateAll()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
        scheduleSnapshot()
    }

    /// `-snapshot <file.png> [-snapshotDelay <seconds>]`: draws the window into a PNG without the
    /// screen (works while the Mac is locked), then quits. Used for screenshots in reviews.
    private func scheduleSnapshot() {
        let defaults = UserDefaults.standard
        guard let path = defaults.string(forKey: "snapshot") else { return }
        let delay = defaults.double(forKey: "snapshotDelay") > 0 ? defaults.double(forKey: "snapshotDelay") : 10
        // `-snapshotSize 1080x700` checks a layout at a given window size.
        if let size = defaults.string(forKey: "snapshotSize")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                NSApp.windows.first?.setContentSize(NSSize(width: size[0], height: size[1]))
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            if let view = NSApp.windows.first(where: { $0.isVisible || $0.contentView != nil })?.contentView,
               let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: path))
            }
            NSApp.terminate(nil)
        }
    }

    /// A real Mole run (the run sheet) is not stopped silently: ask first.
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let session = MainActor.assumeIsolated({ model?.session }), !session.isFinished else { return .terminateNow }
        let alert = NSAlert()
        alert.messageText = "Mole is still working"
        alert.informativeText = "“\(session.title)” has not finished. Quitting stops it where it is."
        alert.addButton(withTitle: "Keep Working")
        alert.addButton(withTitle: "Stop and Quit")
        alert.buttons[1].hasDestructiveAction = true
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }

    func applicationWillTerminate(_ notification: Notification) { Mole.terminateAll() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
