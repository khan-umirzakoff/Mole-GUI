import SwiftUI

/// Runs a Mole dry run with pipes and keeps the parsed result.
@MainActor
final class Scan<Report>: ObservableObject {
    @Published var report: Report?
    @Published var scanning = false
    @Published var failed = false
    private let args: [String]
    private let parse: (String) -> Report

    init(_ args: [String], parse: @escaping (String) -> Report) {
        self.args = args
        self.parse = parse
    }

    func run() async {
        guard !scanning else { return }
        scanning = true
        failed = false
        defer { scanning = false }
        do {
            let data = try await Mole.capture(args)
            report = parse(String(decoding: data, as: UTF8.self))
        } catch {
            failed = true
        }
    }
}

/// The large hero card at the top of every tool page.
struct HeroCard<Actions: View>: View {
    let glow: Glow
    let label: String
    let bytes: Int64?
    let detail: String
    var scanning = false
    @ViewBuilder var actions: Actions

    var body: some View {
        GlowCard(glow: glow, style: .rim, padding: 26) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(label).cardTitle()
                    if scanning {
                        HStack(spacing: 12) {
                            ProgressView().controlSize(.small).tint(.white)
                            Text("Scanning with Mole…").font(.system(size: 22, weight: .medium)).shimmer()
                        }
                        .frame(height: 56, alignment: .leading)
                    } else if let bytes {
                        MetricValue(value: bytes.metric.value, unit: bytes.metric.unit, dot: 7)
                    } else {
                        Text("Not scanned yet").font(.system(size: 26, weight: .medium)).frame(height: 56, alignment: .leading)
                    }
                    Text(detail).caption().lineLimit(2)
                }
                Spacer()
                HStack(spacing: 10) { actions }
            }
        }
        .frame(height: 200)
    }
}

/// Sections of a dry run as cards in two columns.
struct SectionGrid: View {
    let sections: [ReportSection]
    var glow: Glow = .graphite

    var body: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 18), GridItem(.flexible(), spacing: 18)],
                  alignment: .leading, spacing: 18) {
            ForEach(sections) { section in
                GlowCard(glow: glow, style: .plain, padding: 20) {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(section.title).cardTitle()
                            Spacer()
                            if section.bytes > 0 { Text(section.bytes.bytesText).font(.system(size: 13, weight: .semibold)) }
                        }
                        ForEach(section.items) { item in ReportRow(item: item) }
                    }
                }
            }
        }
    }
}

struct ReportRow: View {
    let item: ReportItem

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Circle().fill(dotColor).frame(width: 6, height: 6).alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name).font(.system(size: 13)).foregroundStyle(item.kind == .ok ? Theme.secondaryText : .white)
                if !item.detail.isEmpty {
                    Text(cleanDetail).font(.system(size: 11.5)).foregroundStyle(Theme.tertiaryText).lineLimit(2)
                }
            }
            Spacer()
            switch item.kind {
            case .action:
                if let b = item.bytes, b > 0 { Text(b.bytesText).font(.system(size: 12.5, design: .monospaced)) }
            case .info: Tag(text: "Manual", color: Glow.blue.color)
            case .skipped: Tag(text: "Skipped", color: .orange)
            case .ok: EmptyView()
            }
        }
    }

    private var dotColor: Color {
        switch item.kind {
        case .action: Theme.accent
        case .info: Glow.blue.color
        case .skipped: .orange
        case .ok: .white.opacity(0.25)
        }
    }

    /// The size is already shown on the right; keep the rest of Mole's detail.
    private var cleanDetail: String {
        guard item.kind == .action, let b = item.bytes, b > 0 else { return item.detail }
        return item.detail.components(separatedBy: ", ").filter { ByteSize.first(in: $0) == nil }.joined(separator: ", ")
    }
}

struct Notes: View {
    let notes: [String]

    var body: some View {
        if !notes.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(notes, id: \.self) { note in
                    Label(note, systemImage: "info.circle").font(.system(size: 12.5)).foregroundStyle(Theme.secondaryText)
                }
            }
        }
    }
}

struct EmptyState: View {
    let symbol: String
    let text: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 30, weight: .light))
            Text(text).font(.system(size: 14)).multilineTextAlignment(.center)
        }
        .foregroundStyle(Theme.secondaryText)
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

/// A checkbox that matches the dark cards.
struct CheckDot: View {
    let on: Bool

    var body: some View {
        ZStack {
            Circle().strokeBorder(.white.opacity(on ? 0 : 0.3), lineWidth: 1.5)
            if on {
                Circle().fill(Theme.accent)
                Image(systemName: "checkmark").font(.system(size: 9, weight: .heavy)).foregroundStyle(.black)
            }
        }
        .frame(width: 18, height: 18)
        .animation(Motion.quick, value: on)
    }
}

/// Asks before a destructive step, in the app's words.
struct ConfirmAction: Identifiable {
    let id = UUID()
    let title: String
    let message: String
    let button: String
    let action: () -> Void
}

extension View {
    func confirmation(_ item: Binding<ConfirmAction?>) -> some View {
        alert(item.wrappedValue?.title ?? "", isPresented: Binding(get: { item.wrappedValue != nil },
                                                                     set: { if !$0 { item.wrappedValue = nil } })) {
            Button(item.wrappedValue?.button ?? "OK", role: .destructive) { item.wrappedValue?.action() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(item.wrappedValue?.message ?? "")
        }
    }
}
