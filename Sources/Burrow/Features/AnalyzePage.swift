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

/// Mole's size map of one folder at a time, with a trail for drilling down and back.
@MainActor
final class DiskMap: ObservableObject {
    @Published var trail: [String] = []
    @Published var result: AnalyzeResult?
    @Published var loading = false
    @Published var error: String?
    @Published private(set) var startedAt = Date()
    var onBusyChange: ((Bool) -> Void)?
    private var task: Task<Void, Never>?

    var current: String? { trail.last }

    /// Maps `path` below the current trail; `nil` maps the whole Mac.
    func open(_ path: String?) {
        if let path { trail.append(path) } else { trail = [] }
        reload()
    }

    /// Starts a fresh trail at a top-level place.
    func jump(to path: String?) {
        trail = path.map { [$0] } ?? []
        reload()
    }

    func back(to index: Int) {
        trail = Array(trail.prefix(index + 1))
        reload()
    }

    /// Maps the current folder. A newer request replaces an older one still measuring.
    func reload() {
        task?.cancel()
        let args = ["analyze", "--json"] + (current.map { [$0] } ?? [])
        loading = true
        error = nil
        startedAt = Date()
        onBusyChange?(true)
        task = Task {
            do {
                let r = try await Mole.json(AnalyzeResult.self, args)
                guard !Task.isCancelled else { return }
                result = r
            } catch {
                guard !Task.isCancelled else { return }
                result = nil
                self.error = error.localizedDescription
            }
            loading = false
            onBusyChange?(false)
        }
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
                        let path = place.1.map { ($0 as NSString).expandingTildeInPath }
                        let active = map.trail.first == path || (path == nil && map.trail.isEmpty)
                        Button(place.0) { map.jump(to: path) }
                            .buttonStyle(active ? .pill : .pillSecondary)
                            .accessibilityAddTraits(active ? .isSelected : [])
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
                            Text("Mole is measuring \(currentName)…").font(.system(size: 13, weight: .medium))
                            HStack(spacing: 4) { Text("Large folders take a minute ·"); Elapsed(since: map.startedAt) }.caption()
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(.black.opacity(0.55)))
                        .transition(.opacity)
                    } else if let error = map.error {
                        EmptyState(symbol: "exclamationmark.triangle", text: "Mole could not map \(currentName)", detail: error,
                                   actionTitle: "Try again", action: map.reload)
                    } else if entries.isEmpty {
                        EmptyState(symbol: "square.grid.3x3", text: map.result == nil ? "Pick a place above to map it." : "This folder is empty.")
                    }
                }
                .animation(Motion.quick, value: map.loading)
            }
            .frame(height: 460)

            if !entries.isEmpty { list }
        }
        .confirmation($confirm)
        .onAppear { if map.result == nil, !map.loading, map.error == nil { map.reload() } }
    }

    private var currentName: String {
        guard let path = map.current else { return "this Mac" }
        return (path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent
    }

    private var breadcrumb: some View {
        HStack(spacing: 6) {
            Button("This Mac") { map.jump(to: nil) }.buttonStyle(.plain)
                .foregroundStyle(map.trail.isEmpty ? .white : Theme.secondaryText)
            ForEach(Array(map.trail.enumerated()), id: \.offset) { i, path in
                Image(systemName: "chevron.right").font(.system(size: 10)).foregroundStyle(Theme.tertiaryText)
                Button((path as NSString).lastPathComponent.isEmpty ? path : (path as NSString).lastPathComponent) {
                    map.back(to: i)
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
            if entry.isDirectory { map.open(entry.path) }
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
                    .onTapGesture { if entry.isDirectory { map.open(entry.path) } }
                    .contextMenu { menu(for: entry) }
                }
            }
        }
    }

    @ViewBuilder private func menu(for entry: AnalyzeResult.Entry) -> some View {
        if entry.isDirectory { Button("Open") { map.open(entry.path) } }
        Button("Show in Finder") { NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "") }
        // Only the user's own files: system folders and apps have their own, safer tools.
        if entry.path.hasPrefix(FileManager.default.homeDirectoryForCurrentUser.path + "/") {
            Divider()
            Button("Move to Trash…", role: .destructive) {
                confirm = .init(title: "Move \(entry.name) to the Trash?",
                                message: "\(entry.size.bytesText) at \((entry.path as NSString).abbreviatingWithTildeInPath). You can restore it from the Trash.",
                                button: "Move to Trash") {
                    if Trash.move([entry.path]).isEmpty {
                        map.reload()
                    } else {
                        map.error = "\(entry.name) could not be moved to the Trash. It may belong to macOS or another user."
                    }
                }
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        if panel.runModal() == .OK, let url = panel.url { map.jump(to: url.path) }
    }
}
