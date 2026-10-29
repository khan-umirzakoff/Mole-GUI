import Foundation
import Testing
@testable import Burrow

struct ParserTests {
    @Test func cleanDryRun() {
        let out = """
        \u{1B}[1;35mClean Your Mac\u{1B}[0m
        ◎ System caches need sudo, run sudo -v && mo clean --dry-run for full preview
        ✓ Whitelist: 8 core + 1 custom patterns active
          ↳ /Users/x/Library/Caches/kitty
        ➤ User essentials
          → User app cache · 36 items, 1.30GB dry
          ◎ Trash · skipped, grant Full Disk Access to your terminal
        ➤ Cloud & Office
          ✓ Nothing to clean
        ➤ Large files
          ⊙ pnpm store · 2.78GB · ~/Library/pnpm/store
        ======================================================================
        Dry run complete - no changes made
        Potential space: 10.63GB+ | Items: 524 | Categories: 6
        ======================================================================
        """
        let r = SectionReport.parse(out)
        #expect(r.sections.map(\.title) == ["User essentials", "Cloud & Office", "Large files"])
        #expect(r.sections[0].items[0].name == "User app cache")
        #expect(r.sections[0].items[0].bytes == 1_300_000_000)
        #expect(r.sections[0].items[1].kind == .skipped)
        #expect(r.sections[2].items[0].kind == .info)
        #expect(r.bytes == 1_300_000_000) // manual items are not counted
        #expect(r.notes.count == 1)
        #expect(r.summary.count == 2)
    }

    @Test func purgeAndSlim() {
        let purge = PurgeReport.parse("✓ [DRY RUN] ~/PROJECTS/A/node_modules, 1.5GB\n\r✓ [DRY RUN] ~/PROJECTS/A/apps/web/.next, 20MB\nWould free approximately: 1.52GB | Items: 2")
        #expect(purge.artifacts.count == 2)
        #expect(purge.artifacts[1].project == ("~/PROJECTS/A/apps/web" as NSString).expandingTildeInPath)
        #expect(purge.artifacts[0].project == ("~/PROJECTS/A" as NSString).expandingTildeInPath)
        let slim = SlimReport.parse("→ DRY RUN MODE\n\n  Google Chrome        576.3MB\n  Arc                  350.8MB\n\n2 apps, 927.1MB of Intel code")
        #expect(slim.apps.map(\.name) == ["Google Chrome", "Arc"])
        #expect(slim.bytes == 927_100_000)
    }

    @Test func terminalText() {
        #expect(TerminalText.visible("⠋ Scanning\r\u{1B}[2K✓ Done") == "✓ Done")
        #expect(MoleSession.completeUTF8Length(Data("ab".utf8) + Data([0xE2, 0x9C])) == 2)
        #expect(MoleSession.completeUTF8Length(Data("a✓".utf8)) == 4)
    }

    @Test func treemapFillsRect() {
        let rects = Treemap.layout([6, 6, 4, 3, 2, 2, 1], in: CGRect(x: 0, y: 0, width: 600, height: 400))
        let area = rects.map { $0.width * $0.height }.reduce(0, +)
        #expect(abs(area - 240_000) < 1)
    }

    @Test func installerNames() {
        #expect(InstallerScanner.isInstaller("Claude.dmg"))
        #expect(InstallerScanner.isInstaller("BssPluginSetup.app.zip"))
        #expect(!InstallerScanner.isInstaller("photos.zip"))
    }
}
