import Foundation

// MARK: - Dry-run text reports

struct ReportItem: Identifiable, Hashable {
    enum Kind { case action, info, skipped, ok }
    /// Position in Mole's output, so a re-parse of a growing output keeps the same identity.
    let id: String
    let kind: Kind
    let name: String
    let detail: String
    let bytes: Int64?
}

struct ReportSection: Identifiable, Hashable {
    let id: String
    let title: String
    var items: [ReportItem]
    var bytes: Int64 { items.filter { $0.kind == .action }.compactMap(\.bytes).reduce(0, +) }
}

/// Mole's sectioned dry-run output (`mo clean -n`, `mo optimize -n`).
struct SectionReport {
    var notes: [String] = []
    var sections: [ReportSection] = []
    var summary: [String] = []

    /// Sum of the rows. Rows overlap (a cache folder and a cache inside it), so this is only a
    /// running figure while Mole scans; `total` is what a clean frees.
    var bytes: Int64 { sections.map(\.bytes).reduce(0, +) }
    var actionCount: Int { sections.flatMap(\.items).filter { $0.kind == .action }.count }

    /// Mole's own "Potential space" (de-duplicated), "+" when some sizes were unknown.
    var potential: Int64?
    var potentialIsLowerBound = false
    var itemCount: Int?
    var categoryCount: Int?

    /// What a clean frees: Mole's de-duplicated figure, else the row sum.
    var total: Int64 { potential ?? bytes }

    /// "622 items in 6 categories", from Mole's summary.
    var tally: String? {
        guard let items = itemCount else { return nil }
        let first = "\(items.formatted()) item\(items == 1 ? "" : "s")"
        guard let cats = categoryCount else { return first }
        return first + " in \(cats.formatted()) categor\(cats == 1 ? "y" : "ies")"
    }

    static func parse(_ output: String) -> SectionReport {
        var report = SectionReport()
        var inSummary = false
        for line in TerminalText.lines(output) {
            if line.hasPrefix("====") { inSummary.toggle(); continue }
            if inSummary {
                report.summary.append(line)
                // "Potential space: 11.27GB+ | Items: 622 | Categories: 6"
                if line.hasPrefix("Potential space:") {
                    for part in line.components(separatedBy: " | ") {
                        let value = part.components(separatedBy: ": ").last ?? ""
                        if part.hasPrefix("Potential space") {
                            report.potential = ByteSize.first(in: value)
                            report.potentialIsLowerBound = value.hasSuffix("+")
                        } else if part.hasPrefix("Items") {
                            report.itemCount = Int(value)
                        } else if part.hasPrefix("Categories") {
                            report.categoryCount = Int(value)
                        }
                    }
                }
                continue
            }
            if line.hasPrefix("➤") {
                let title = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                report.sections.append(.init(id: "\(report.sections.count)-\(title)", title: title, items: []))
                continue
            }
            guard let icon = line.first else { continue }
            let kind: ReportItem.Kind
            switch icon {
            case "→": kind = .action
            case "⊙": kind = .info
            case "◎": kind = .skipped
            case "✓": kind = .ok
            default: continue
            }
            let body = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            if report.sections.isEmpty {
                // The dry-run banner and the whitelist count are Mole talking to the terminal.
                if !body.hasPrefix("DRY RUN"), kind != .ok || !body.hasPrefix("Whitelist") { report.notes.append(body) }
                continue
            }
            let parts = body.components(separatedBy: " · ")
            let name: String, detail: String
            if parts.count > 1 {
                name = parts[0]
                detail = parts.dropFirst().joined(separator: " · ")
            } else if let comma = body.range(of: ", ") {
                name = String(body[..<comma.lowerBound])
                detail = String(body[comma.upperBound...])
            } else {
                name = body
                detail = ""
            }
            let bytes = detail.contains("protected") && detail.hasPrefix("0") ? nil : ByteSize.first(in: detail)
            let last = report.sections.count - 1
            report.sections[last].items.append(
                .init(id: "\(last).\(report.sections[last].items.count)", kind: kind, name: name,
                      detail: detail.replacingOccurrences(of: " dry", with: ""), bytes: bytes))
        }
        report.sections.removeAll { $0.items.isEmpty }
        return report
    }
}

/// `mo purge --dry-run`: one build artifact per line.
struct PurgeReport {
    struct Artifact: Identifiable, Hashable {
        var id: String { path }
        let path: String
        let bytes: Int64
        var expandedPath: String { (path as NSString).expandingTildeInPath }
        var kind: String { (path as NSString).lastPathComponent }
        /// The project folder the artifact belongs to.
        var project: String {
            var url = URL(fileURLWithPath: expandedPath).deletingLastPathComponent()
            while ["packages", "apps", "plugin", "package", "android", "app"].contains(url.lastPathComponent) {
                url.deleteLastPathComponent()
            }
            return url.path
        }
    }

    var artifacts: [Artifact] = []
    var summary = ""
    /// Mole's warnings, for example scan roots it had to skip.
    var notes: [String] = []
    /// Scan roots Mole could not finish ("~", "~/PROJECTS/Big"), listed under its warning.
    var skippedRoots: [String] = []
    var bytes: Int64 { artifacts.map(\.bytes).reduce(0, +) }

    private static let skippedRoot = try! NSRegularExpression(pattern: "^(.+) \\(status [0-9]+\\)$")

    static func parse(_ output: String) -> PurgeReport {
        var report = PurgeReport()
        var inSkipped = false
        for line in TerminalText.lines(output) {
            if inSkipped {
                let ns = NSRange(line.startIndex..., in: line)
                if let m = skippedRoot.firstMatch(in: line, range: ns), let r = Range(m.range(at: 1), in: line) {
                    report.skippedRoots.append(String(line[r]))
                    continue
                }
                if line.hasPrefix("and "), line.hasSuffix(" more") { continue }
                inSkipped = false
            }
            if line.hasPrefix("◎ Skipped") {
                // The heading ends with a colon; the roots follow on their own lines.
                var note = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
                if note.hasSuffix(":") { note.removeLast() }
                report.notes.append(note)
                inSkipped = true
            } else if let r = line.range(of: "[DRY RUN] ") {
                let rest = line[r.upperBound...]
                guard let comma = rest.range(of: ", ", options: .backwards) else { continue }
                report.artifacts.append(.init(path: String(rest[..<comma.lowerBound]),
                                              bytes: ByteSize.first(in: String(rest[comma.upperBound...])) ?? 0))
            } else if line.hasPrefix("Would free") {
                report.summary = line
            }
        }
        report.artifacts.sort { $0.bytes > $1.bytes }
        if !report.skippedRoots.isEmpty, let i = report.notes.firstIndex(where: { $0.hasPrefix("Skipped") }) {
            report.notes[i] += ": " + report.skippedRoots.joined(separator: ", ")
        }
        return report
    }
}

/// `mo slim --dry-run`: universal apps and their Intel code size.
struct SlimReport {
    struct App: Identifiable, Hashable {
        var id: String { name }
        let name: String
        let bytes: Int64
    }

    var apps: [App] = []
    var summary = ""
    var bytes: Int64 { apps.map(\.bytes).reduce(0, +) }

    private static let row = try! NSRegularExpression(pattern: "^(.+?)\\s{2,}([0-9.]+\\s?(?:TB|GB|MB|KB|B))$")

    static func parse(_ output: String) -> SlimReport {
        var report = SlimReport()
        for line in TerminalText.lines(output) {
            if line.contains("of Intel code") { report.summary = line; continue }
            let ns = NSRange(line.startIndex..., in: line)
            guard let m = row.firstMatch(in: line, range: ns),
                  let n = Range(m.range(at: 1), in: line), let s = Range(m.range(at: 2), in: line) else { continue }
            report.apps.append(.init(name: String(line[n]), bytes: ByteSize.first(in: String(line[s])) ?? 0))
        }
        return report
    }
}

// MARK: - JSON reports

struct SystemStatus: Decodable {
    struct Hardware: Decodable { let model: String?; let cpu_model: String?; let total_ram: String?; let disk_size: String?; let os_version: String? }
    struct CPU: Decodable { let usage: Double; let per_core: [Double]?; let load1: Double?; let core_count: Int?; let p_core_count: Int?; let e_core_count: Int? }
    struct Memory: Decodable { let used: Int64; let total: Int64; let available: Int64?; let used_percent: Double; let swap_used: Int64?; let cached: Int64? }
    struct Disk: Decodable { let mount: String; let used: Int64; let total: Int64; let used_percent: Double?; let purgeable: Int64?; let external: Bool? }
    struct DiskIO: Decodable { let read_rate: Double?; let write_rate: Double? }
    struct Network: Decodable { let name: String; let rx_rate_mbs: Double?; let tx_rate_mbs: Double?; let ip: String? }
    struct Battery: Decodable { let percent: Double?; let status: String?; let time_left: String?; let health: String?; let cycle_count: Int?; let capacity: Double? }
    struct Thermal: Decodable { let cpu_temp: Double?; let battery_temp: Double?; let system_power: Double?; let adapter_power: Double? }
    struct Proc: Decodable, Identifiable { let pid: Int; let name: String; let cpu: Double; let memory: Double?; let memory_bytes: Int64?; var id: Int { pid } }

    let host: String?
    let uptime: String?
    let procs: Int?
    let hardware: Hardware?
    let health_score: Int?
    let health_score_msg: String?
    let cpu: CPU?
    let memory: Memory?
    let disks: [Disk]?
    let disk_io: DiskIO?
    let network: [Network]?
    let batteries: [Battery]?
    let thermal: Thermal?
    let trash_size: Int64?
    let top_processes: [Proc]?

    var rootDisk: Disk? { disks?.first { $0.mount == "/" } ?? disks?.first }
}

struct AnalyzeResult: Decodable {
    struct Entry: Decodable, Identifiable, Hashable {
        let name: String
        let path: String
        let size: Int64
        let is_dir: Bool?
        let last_access: String?
        /// Whole-Mac overview only: a summary such as "Old Downloads (90d+)", whose `path` is the
        /// folder it was found in and whose `size` is only the part it describes.
        let insight: Bool?
        let cleanable: Bool?
        var id: String { path + name }
        var isDirectory: Bool { is_dir ?? false }
        var isInsight: Bool { insight ?? false }
    }

    let path: String?
    /// True for the whole-Mac tour: its entries overlap (Home contains User Library) and do not add up.
    let overview: Bool?
    let scan_status: String?
    let entries: [Entry]?
    let large_files: [Entry]?
}

struct HistoryResult: Decodable {
    struct Session: Decodable, Identifiable, Hashable {
        struct Actions: Decodable, Hashable { let removed: Int?; let trashed: Int?; let skipped: Int?; let failed: Int?; let rebuilt: Int? }
        let command: String
        let started_at: String
        let ended_at: String?
        let items: Int?
        let size: String?
        let failed_tasks: Int?
        let actions: Actions?
        var id: String { command + started_at }
    }
    struct Deletion: Decodable, Identifiable, Hashable {
        let time: String?
        let path: String?
        let size: String?
        let action: String?
        let command: String?
        var id: String { (time ?? "") + (path ?? "") }
    }

    let sessions: [Session]?
    let deletions: [Deletion]?
}

struct InstalledApp: Decodable, Identifiable, Hashable {
    let name: String
    let bundle_id: String?
    let source: String?
    let uninstall_name: String
    let path: String
    /// Mole's own measurement ("1.2GB"), cached by Mole between runs.
    let size: String?
    var id: String { path }
    var bytes: Int64? { size.flatMap { ByteSize.first(in: $0) } }
}
