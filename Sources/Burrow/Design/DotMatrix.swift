import SwiftUI

/// Renders numbers and short units in the dotted LED style of the reference designs.
struct DotMatrixText: View {
    let text: String
    var dot: CGFloat = 4
    var color: Color = .white

    private static let glyphs: [Character: [String]] = [
        "0": ["01110", "10001", "10011", "10101", "11001", "10001", "01110"],
        "1": ["00100", "01100", "00100", "00100", "00100", "00100", "01110"],
        "2": ["01110", "10001", "00001", "00010", "00100", "01000", "11111"],
        "3": ["11110", "00001", "00001", "01110", "00001", "00001", "11110"],
        "4": ["00010", "00110", "01010", "10010", "11111", "00010", "00010"],
        "5": ["11111", "10000", "11110", "00001", "00001", "10001", "01110"],
        "6": ["00110", "01000", "10000", "11110", "10001", "10001", "01110"],
        "7": ["11111", "00001", "00010", "00100", "01000", "01000", "01000"],
        "8": ["01110", "10001", "10001", "01110", "10001", "10001", "01110"],
        "9": ["01110", "10001", "10001", "01111", "00001", "00010", "01100"],
        ".": ["0", "0", "0", "0", "0", "0", "1"],
        ",": ["0", "0", "0", "0", "0", "1", "1"],
        ":": ["0", "0", "1", "0", "1", "0", "0"],
        "%": ["11001", "11010", "00010", "00100", "01000", "01011", "10011"],
        "+": ["000", "000", "010", "111", "010", "000", "000"],
        "-": ["000", "000", "000", "111", "000", "000", "000"],
        "/": ["00001", "00010", "00010", "00100", "01000", "01000", "10000"],
        " ": ["00", "00", "00", "00", "00", "00", "00"],
    ]

    var body: some View {
        let rows = layout()
        let width = CGFloat(rows.first?.count ?? 0) * dot * 1.6
        Canvas { ctx, _ in
            let step = dot * 1.6
            for (y, row) in rows.enumerated() {
                for (x, on) in row.enumerated() where on {
                    ctx.fill(Path(ellipseIn: CGRect(x: CGFloat(x) * step, y: CGFloat(y) * step, width: dot, height: dot)),
                             with: .color(color))
                }
            }
        }
        .frame(width: width, height: 7 * dot * 1.6)
        .accessibilityElement()
        .accessibilityLabel(text)
    }

    /// One boolean grid for the whole string, with a blank column between glyphs.
    private func layout() -> [[Bool]] {
        var rows = Array(repeating: [Bool](), count: 7)
        for ch in text {
            guard let g = Self.glyphs[ch] else { continue }
            for r in 0..<7 {
                if !rows[r].isEmpty { rows[r].append(false) }
                rows[r] += g[r].map { $0 == "1" }
            }
        }
        return rows
    }
}

/// A big dotted number with a plain unit next to it ("120.8" GB).
/// `live` values (refreshed every few seconds) change in place; others cross-fade.
struct MetricValue: View {
    let value: String
    var unit: String = ""
    var dot: CGFloat = 4
    var live = false

    var body: some View {
        // Narrow cards (the minimum window size) get smaller dots instead of clipped digits.
        ViewThatFits(in: .horizontal) {
            row(dot)
            row(dot * 0.8)
            row(dot * 0.62)
        }
        .animation(live ? nil : Motion.spring, value: value)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(unit.isEmpty ? value : "\(value) \(unit)")
    }

    private func row(_ dot: CGFloat) -> some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            if live {
                DotMatrixText(text: value, dot: dot)
            } else {
                DotMatrixText(text: value, dot: dot)
                    .id(value)
                    .transition(.blurFade)
            }
            if !unit.isEmpty {
                Text(unit).font(.system(size: max(11, dot * 3), weight: .regular)).foregroundStyle(Theme.secondaryText)
                    .lineLimit(1).fixedSize()
            }
        }
    }
}

extension Int64 {
    /// Splits a byte count into a dotted number and its unit.
    var metric: (value: String, unit: String) {
        let parts = ByteSize.format(self).split(separator: " ")
        return (String(parts.first ?? "0"), parts.count > 1 ? String(parts[1]) : "")
    }
}
