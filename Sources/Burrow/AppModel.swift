import SwiftUI

enum Page: String, CaseIterable, Identifiable {
    case overview, clean, uninstall, optimize, analyze, projects, installers, slim, history, settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: "Overview"
        case .clean: "Clean"
        case .uninstall: "Uninstall"
        case .optimize: "Optimize"
        case .analyze: "Disk Map"
        case .projects: "Projects"
        case .installers: "Installers"
        case .slim: "Slim Apps"
        case .history: "History"
        case .settings: "Settings"
        }
    }

    var symbol: String {
        switch self {
        case .overview: "circle.hexagongrid"
        case .clean: "sparkles"
        case .uninstall: "trash"
        case .optimize: "bolt"
        case .analyze: "square.grid.3x3.square"
        case .projects: "shippingbox"
        case .installers: "opticaldiscdrive"
        case .slim: "scissors"
        case .history: "clock.arrow.circlepath"
        case .settings: "slider.horizontal.3"
        }
    }

    var glow: Glow {
        switch self {
        case .overview, .history: .violet
        case .clean, .slim: .magenta
        case .uninstall, .installers: .ember
        case .optimize, .settings: .sage
        case .analyze, .projects: .blue
        }
    }

    var subtitle: String {
        switch self {
        case .overview: "Live health of this Mac"
        case .clean: "Caches, logs and leftovers of removed apps"
        case .uninstall: "Remove apps with everything they left behind"
        case .optimize: "Refresh system caches and services"
        case .analyze: "See what takes the space"
        case .projects: "Build folders of projects you are not touching"
        case .installers: "Disk images and packages you no longer need"
        case .slim: "Drop the Intel half of universal apps"
        case .history: "Everything Mole changed, newest first"
        case .settings: "Protection rules, scan folders, Touch ID"
        }
    }

    var shortcut: KeyEquivalent {
        let keys: [Page: Character] = [.overview: "1", .clean: "2", .uninstall: "3", .optimize: "4", .analyze: "5",
                                       .projects: "6", .installers: "7", .slim: "8", .history: "9", .settings: ","]
        return KeyEquivalent(keys[self] ?? "0")
    }
}

/// Shared state: navigation, the running Mole session and the last scan of each tool.
@MainActor
final class AppModel: ObservableObject {
    @Published var page: Page = .overview
    @Published var session: MoleSession?

    let clean = Scan(["clean", "--dry-run"], parse: SectionReport.parse)
    let optimize = Scan(["optimize", "--dry-run"], parse: SectionReport.parse)
    let purge = Scan(["purge", "--dry-run"], parse: PurgeReport.parse)
    let slim = Scan(["slim", "--dry-run"], parse: SlimReport.parse)
    let apps = AppCatalog()
    let diskMap = DiskMap()
    let installers = InstallerStore()

    /// Starts a Mole command in the run sheet. `onFinish` runs after the user closes the sheet.
    func run(_ title: String, _ args: [String], responders: [MoleSession.Responder] = [],
             onFinish: (() -> Void)? = nil) {
        let s = MoleSession(title: title, args: args, responders: responders)
        finishHandler = onFinish
        session = s
        s.start()
    }

    private var finishHandler: (() -> Void)?

    func closeSession() {
        session?.cancel()
        session = nil
        finishHandler?()
        finishHandler = nil
    }
}
