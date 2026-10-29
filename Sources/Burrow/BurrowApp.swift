import SwiftUI

@main
struct BurrowApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Burrow") {
            RootView()
                .environmentObject(model)
                .onAppear { delegate.model = model }
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
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                Mole.terminateAll()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
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
