import SwiftUI

@main
struct BurrowApp: App {
    @NSApplicationDelegateAdaptor private var delegate: AppDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup("Burrow") {
            RootView()
                .environmentObject(model)
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
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Started from `swift run` the binary is not an app bundle yet; make it a normal app.
        NSApp.setActivationPolicy(.regular)
        NSApp.activate()
    }

    func applicationWillTerminate(_ notification: Notification) { Mole.terminateAll() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
}
