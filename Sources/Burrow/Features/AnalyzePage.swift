import SwiftUI

/// Squarified treemap layout (Bruls, Huizing, van Wijk): rectangles close to squares.
enum Treemap {
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return values.map { _ in .zero } }
        let scale = rect.width * rect.height / total
        var areas = values.map { $0 * scale }[...]
        var out: [CGRect] = []
        var free = rect
        var row: [Double] = []
        while let next = areas.first {
            let side = min(free.width, free.height)
            if row.isEmpty || worst(row + [next], side) <= worst(row, side) {
                row.append(next)
                areas.removeFirst()
            } else {
                out += place(row, in: &free)
                row = []
            }
        }
        if !row.isEmpty { out += place(row, in: &free) }
        return out
    }

    private static func worst(_ row: [Double], _ side: Double) -> Double {
        let s = row.reduce(0, +)
        guard let mx = row.max(), let mn = row.min(), s > 0, mn > 0 else { return .infinity }
        return max(side * side * mx / (s * s), s * s / (side * side * mn))
    }

    private static func place(_ row: [Double], in free: inout CGRect) -> [CGRect] {
        let s = row.reduce(0, +)
        var rects: [CGRect] = []
        if free.width >= free.height {
            let w = s / free.height
            var y = free.minY
            for a in row { let h = a / w; rects.append(CGRect(x: free.minX, y: y, width: w, height: h)); y += h }
            free = CGRect(x: free.minX + w, y: free.minY, width: free.width - w, height: free.height)
        } else {
            let h = s / free.width
            var x = free.minX
            for a in row { let w = a / h; rects.append(CGRect(x: x, y: free.minY, width: w, height: h)); x += w }
            free = CGRect(x: free.minX, y: free.minY + h, width: free.width, height: free.height - h)
        }
        return rects
    }
}

@MainActor
final class DiskMap: ObservableObject {
    @Published var trail: [String] = []
    @Published var result: AnalyzeResult?
    @Published var loading = false

    var current: String? { trail.last }

    func open(_ path: String?) async {
        if let path { trail.append(path) } else { trail = [] }
        await reload()
    }

    func back(to index: Int) async {
        trail = Array(trail.prefix(index + 1))
        await reload()
    }

    func reload() async {
        loading = true
        defer { loading = false }
        result = try? await Mole.json(AnalyzeResult.self, ["analyze", "--json"] + (current.map { [$0] } ?? []))
    }
}

struct AnalyzePage: View {
    @ObservedObject var map: DiskMap
    @ViewState private var confirm: ConfirmAction?
    @ViewState private var hovered: String?

    private let places: [(String, String?)] = [
        ("Whole Mac", nil), ("Home", "~"), ("Downloads", "~/Downloads"), ("Documents", "~/Documents"),
        ("Library", "~/Library"), ("Applications", "/Applications"), ("External drives", "/Volumes"),
    ]

    private var entries: [AnalyzeResult.Entry] {
        Array((map.result?.entries ?? []).filter { $0.size > 0 }.sorted { $0.size > $1.size }.prefix(30))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            ScrollView(.horizontal) {
                HStack(spacing: 8) {
                    ForEach(places, id: \.0) { place in
                        Button(place.0) {
                            map.trail = []
                            Task { await map.open(place.1.map { ($0 as NSString).expandingTildeInPath }) }
                        }
                        .buttonStyle(.pillSecondary)
                    }
                    Button { choose() } label: { Label("Choose…", systemImage: "folder") }.buttonStyle(.pillSecondary)
                }
            }
            .scrollIndicators(.never)

            breadcrumb

            GlowCard(glow: .blue, style: .plain, padding: 10) {
                GeometryReader { geo in
                    let rects = Treemap.layout(entries.map { Double($0.size) }, in: CGRect(origin: .zero, size: geo.size))
                    ZStack(alignment: .topLeading) {
                        ForEach(Array(entries.enumerated()), id: \.element.id) { i, entry in
                            tile(entry, index: i, rect: rects[i])
                        }
                    }
                }
                .animation(Motion.spring, value: entries)
                .overlay {
                    if map.loading {
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("Mole is measuring…").caption()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(.black.opacity(0.5))
                    } else if entries.isEmpty {
                        EmptyState(symbol: "square.grid.3x3", text: "Pick a place above to map it.")
                    }
                }
            }
            .frame(height: 460)

            if !entries.isEmpty { list }
        }
        .confirmation($confirm)
        .task { if map.result == nil { await map.open(nil) } }
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button("Overview") { Task { await map.open(nil) } }.buttonStyle(.plain).foregroundStyle(Theme.secondaryText)
            ForEach(Array(map.trail.enumerated()), id: \.offset) { i, path in
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
                Button((path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent) {
                    Task { await map.back(to: i) }
                }
                .buttonStyle(.plain)
                .foregroundStyle(i == map.trail.count - 1 ? .white : Theme.secondaryText)
            }
            Spacer()
            if let total = map.result?.entries?.map(\.size).reduce(0, +), total > 0 {
                Text(total.bytesText).font(.system(size: 13, weight: .semibold))
            }
        }
        .font(.system(size: 13))
    }

    private func tile(_ entry: AnalyzeResult.Entry, index: Int, rect: CGRect) -> some View {
        let glow = [Glow.blue, .violet, .magenta, .ember, .sage][index % 5]
        let big = rect.width > 90 && rect.height > 50
        return Button {
            if entry.isDirectory { Task { await map.open(entry.path) } }
        } label: {
            ZStack(alignment: .bottomLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(RadialGradient(colors: [glow.color.opacity(hovered == entry.id ? 0.95 : 0.7), glow.color.opacity(0.18)],
                                         center: .bottomTrailing, startRadius: 0, endRadius: max(rect.width, rect.height)))
                RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(.white.opacity(0.14))
                if big {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(entry.name).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                        Text(entry.size.bytesText).font(.system(size: 11)).foregroundStyle(.white.opacity(0.75))
                    }
                    .padding(10)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(width: max(rect.width - 4, 0), height: max(rect.height - 4, 0))
        .offset(x: rect.minX + 2, y: rect.minY + 2)
        .onHover { hovered = $0 ? entry.id : (hovered == entry.id ? nil : hovered) }
        .help("\(entry.name) — \(entry.size.bytesText)")
        .contextMenu { menu(for: entry) }
    }

    private var list: some View {
        let top = Double(entries.first?.size ?? 1)
        return GlowCard(glow: .graphite, style: .plain, padding: 18) {
            VStack(spacing: 10) {
                ForEach(entries) { entry in
                    HStack(spacing: 12) {
                        Image(systemName: entry.isDirectory ? "folder.fill" : "doc.fill")
                            .foregroundStyle(entry.isDirectory ? Glow.blue.color : Theme.secondaryText).frame(width: 18)
                        Text(entry.name).font(.system(size: 13)).lineLimit(1)
                        Spacer()
                        DotMeter(value: Double(entry.size) / top, count: 24, color: Glow.blue.color)
                        Text(entry.size.bytesText).font(.system(size: 12.5, design: .monospaced)).frame(width: 84, alignment: .trailing)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { if entry.isDirectory { Task { await map.open(entry.path) } } }
                    .contextMenu { menu(for: entry) }
                }
            }
        }
    }

    @ViewBuilder private func menu(for entry: AnalyzeResult.Entry) -> some View {
        if entry.isDirectory { Button("Open") { Task { await map.open(entry.path) } } }
        Button("Show in Finder") { NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "") }
        Divider()
        Button("Move to Trash…", role: .destructive) {
            confirm = .init(title: "Move \(entry.name) to the Trash?",
                            message: "\(entry.size.bytesText) at \(entry.path). You can restore it from the Trash.",
                            button: "Move to Trash") {
                try? FileManager.default.trashItem(at: URL(fileURLWithPath: entry.path), resultingItemURL: nil)
                Task { await map.reload() }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url {
            map.trail = []
            Task { await map.open(url.path) }
        }
    }
}
