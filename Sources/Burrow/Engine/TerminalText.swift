import Foundation

/// Turns raw terminal output into plain lines: strips escape sequences and resolves
/// carriage-return overwrites (spinners, progress bars) to their final text.
enum TerminalText {
    private static let escape = try! NSRegularExpression(
        pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}\u{1B}]*(\u{07}|\u{1B}\\\\)|\u{1B}[()][0-9A-Za-z]|\u{1B}[=>78cDEHM]")

    static func strip(_ s: String) -> String {
        let range = NSRange(s.startIndex..., in: s)
        return escape.stringByReplacingMatches(in: s, range: range, withTemplate: "")
    }

    /// The visible text of one terminal line: the part after the last carriage return.
    static func visible(_ raw: String) -> String {
        let plain = strip(raw)
        let parts = plain.split(separator: "\r", omittingEmptySubsequences: false)
        let last = parts.last(where: { !$0.trimmingCharacters(in: .whitespaces).isEmpty }) ?? ""
        return String(last).replacingOccurrences(of: "\u{08}", with: "")
            .trimmingCharacters(in: .whitespaces.union(.controlCharacters))
    }

    /// Splits a block of output (for example a whole dry run) into visible, non-empty lines.
    static func lines(_ output: String) -> [String] {
        // "\r\n" is a single Character in Swift, so it never equals "\n"; normalise it first.
        output.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
            .map { visible(String($0)) }
            .filter { !$0.isEmpty }
    }
}

/// Parses Mole's human sizes ("1.30GB", "553KB", "0B") into bytes.
enum ByteSize {
    private static let pattern = try! NSRegularExpression(pattern: "([0-9]+(?:\\.[0-9]+)?)\\s?(TB|GB|MB|KB|B)\\b")

    static func first(in s: String) -> Int64? {
        guard let m = pattern.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let n = Range(m.range(at: 1), in: s), let u = Range(m.range(at: 2), in: s),
              let value = Double(s[n]) else { return nil }
        let mult: Double = ["B": 1, "KB": 1e3, "MB": 1e6, "GB": 1e9, "TB": 1e12][String(s[u])] ?? 1
        return Int64(value * mult)
    }

    /// "1.3 GB"; zero stays a number ("0 KB") so the dotted numerals can draw it. Always a decimal
    /// point, whatever the locale: it matches Mole's figures, and a dotted "11,27" reads like a clock.
    static func format(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .decimal, spellsOutZero: false).locale(Locale(identifier: "en_US_POSIX")))
    }
}
