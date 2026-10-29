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

struct BehaviourTests {
    @Test func zeroBytesStayNumeric() {
        #expect(Int64(0).metric.value.allSatisfy { $0.isNumber || $0 == "." || $0 == "," })
        #expect(ByteSize.format(0).contains("0"))
    }

    @Test func reportIdsSurviveReparse() {
        let partial = "➤ User essentials\n  → User app cache · 36 items, 1.30GB dry\n"
        let full = partial + "  → User app logs · 3 items, 3.7MB dry\n➤ Browsers\n  → Chrome cache · 11.1MB dry\n"
        let a = SectionReport.parse(partial), b = SectionReport.parse(full)
        #expect(a.sections[0].id == b.sections[0].id)
        #expect(a.sections[0].items[0].id == b.sections[0].items[0].id)
        #expect(Set(b.sections.flatMap(\.items).map(\.id)).count == 3)
    }

    @Test func scanStatusLine() {
        #expect(Scan<SectionReport>.describe("→ User app cache · 38 items, 1.41GB dry") == "User app cache")
        #expect(Scan<SectionReport>.describe("→ Arc Service Worker, would clean 40.1MB, 0 protected") == "Arc Service Worker")
    }

    @Test func purgeNotes() {
        let r = PurgeReport.parse("◎ Skipped 1 project scan root because scanning did not complete:\n  ~/P (status 124)\n✓ [DRY RUN] ~/P/a/node_modules, 1GB")
        #expect(r.notes.count == 1)
        #expect(r.artifacts.count == 1)
    }

    @Test func appSizeFromMole() throws {
        let json = #"[{"name":"Steam","bundle_id":"com.valvesoftware.steam","source":"App","uninstall_name":"Steam","path":"/Applications/Steam.app","size":"11.3MB"}]"#
        let apps = try JSONDecoder().decode([InstalledApp].self, from: Data(json.utf8))
        #expect(apps[0].bytes == 11_300_000)
    }

    @Test func historyHidesPreviews() throws {
        let json = #"{"sessions":[{"command":"clean-dry-run","started_at":"2026-10-30 03:20:08","items":9,"size":"1GB"},{"command":"uninstall","started_at":"2026-10-30 03:20:06","items":0,"size":"0B","actions":{"removed":0}},{"command":"clean","started_at":"2026-10-29 10:00:00","items":12,"size":"2GB"}]}"#
        let h = try JSONDecoder().decode(HistoryResult.self, from: Data(json.utf8))
        #expect(h.sessions?.filter(\.changedSomething).map(\.command) == ["clean"])
        #expect(h.sessions?[0].title == "Clean")
    }

    @Test func quickRepliesForMolePrompts() {
        let sudo = QuickReply.options(for: "→ System caches need sudo. Enter continue, Space skip:")
        #expect(sudo.map(\.label) == ["Continue", "Skip"])
        #expect(sudo[0].keys == "\r" && sudo[1].keys == " ")
        let purge = QuickReply.options(for: "→ Remove 3 artifacts, 1.2GB  Enter confirm, ESC cancel:")
        #expect(purge.map(\.label) == ["Confirm", "Cancel"])
    }

    /// Runs the bundled Mole; only harmless invocations (version, a rejected flag).
    @Test func captureStreamsAndReportsFailure() async throws {
        var seen: [String] = []
        let data = try await Mole.capture(["--version"]) { seen.append($0) }
        #expect(String(decoding: data, as: UTF8.self).contains("Mole version"))
        try await Task.sleep(for: .milliseconds(100))
        #expect(seen.contains { $0.contains("Mole version") })
        await #expect(throws: MoleError.self) { _ = try await Mole.capture(["purge", "--no-such-flag"]) }
    }
}
