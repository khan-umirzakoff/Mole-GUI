import SwiftUI

/// The glow palette: each card gets one hue that bleeds from its edges or its core.
enum Glow: CaseIterable {
    case magenta, violet, blue, ember, sage, graphite

    var color: Color {
        switch self {
        case .magenta: Color(red: 0.86, green: 0.27, blue: 0.62)
        case .violet: Color(red: 0.55, green: 0.38, blue: 0.98)
        case .blue: Color(red: 0.25, green: 0.38, blue: 1.0)
        case .ember: Color(red: 0.94, green: 0.40, blue: 0.24)
        case .sage: Color(red: 0.43, green: 0.58, blue: 0.53)
        case .graphite: Color(white: 0.42)
        }
    }
}

enum Theme {
    static let background = Color(red: 0.02, green: 0.02, blue: 0.03)
    static let surface = Color.white.opacity(0.05)
    static let hairline = Color.white.opacity(0.09)
    static let primaryText = Color.white
    static let secondaryText = Color.white.opacity(0.58)
    static let tertiaryText = Color.white.opacity(0.36)
    static let accent = Color(red: 0.84, green: 0.96, blue: 0.35)
    static let danger = Color(red: 1.0, green: 0.42, blue: 0.38)
    static let radius: CGFloat = 30
}

// MARK: - Glow card

enum GlowStyle { case rim, core, plain }

struct GlowCard<Content: View>: View {
    var glow: Glow = .graphite
    var style: GlowStyle = .core
    var padding: CGFloat = 22
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background { GlowSurface(glow: glow, style: style) }
            .clipShape(RoundedRectangle(cornerRadius: Theme.radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Theme.radius, style: .continuous)
                    .strokeBorder(LinearGradient(colors: [.white.opacity(0.22), .white.opacity(0.03), .white.opacity(0.08)],
                                                 startPoint: .top, endPoint: .bottom), lineWidth: 1)
            }
            .shadow(color: style == .plain ? .clear : glow.color.opacity(0.22), radius: 28, y: 10)
            .accessibilityElement(children: .contain)
            .reveal()
    }
}

struct GlowSurface: View {
    let glow: Glow
    let style: GlowStyle

    var body: some View {
        GeometryReader { geo in
            let side = max(geo.size.width, geo.size.height)
            ZStack {
                switch style {
                case .rim:
                    // Coloured edges with a dark, soft core.
                    glow.color
                    RadialGradient(colors: [.black.opacity(0.92), .black.opacity(0.55), .clear],
                                   center: .init(x: 0.5, y: 0.55), startRadius: 0, endRadius: side * 0.55)
                        .blur(radius: 18)
                case .core:
                    // Dark card lit from inside.
                    Color(white: 0.06)
                    RadialGradient(colors: [glow.color.opacity(0.95), glow.color.opacity(0.35), .clear],
                                   center: .init(x: 0.62, y: 0.78), startRadius: 0, endRadius: side * 0.62)
                        .blur(radius: 30)
                case .plain:
                    Color.white.opacity(0.045)
                }
                LinearGradient(colors: [.white.opacity(0.10), .clear], startPoint: .top, endPoint: .center)
            }
        }
    }
}

// MARK: - Background

/// A faint dot grid like the reference screens; drawn once per size.
struct DotGrid: View {
    var spacing: CGFloat = 16
    var opacity: Double = 0.07

    var body: some View {
        Canvas { ctx, size in
            var path = Path()
            var y: CGFloat = spacing / 2
            while y < size.height {
                var x: CGFloat = spacing / 2
                while x < size.width {
                    path.addEllipse(in: CGRect(x: x, y: y, width: 1.4, height: 1.4))
                    x += spacing
                }
                y += spacing
            }
            ctx.fill(path, with: .color(.white.opacity(opacity)))
        }
        .allowsHitTesting(false)
    }
}

/// Large, slow colour blobs behind the whole window.
struct AmbientBackground: View {
    var tint: Glow = .violet
    @ViewState private var drift = false

    var body: some View {
        ZStack {
            Theme.background
            Circle().fill(tint.color.opacity(0.28)).frame(width: 620).blur(radius: 160)
                .offset(x: drift ? 300 : 400, y: drift ? -250 : -330)
            Circle().fill(Glow.blue.color.opacity(0.16)).frame(width: 520).blur(radius: 170)
                .offset(x: drift ? -360 : -460, y: drift ? 380 : 300)
            DotGrid()
        }
        .drawingGroup()
        .ignoresSafeArea()
        .animation(.easeInOut(duration: 1.2), value: tint)
        .onAppear {
            guard !Motion.reduced else { return }
            withAnimation(.easeInOut(duration: 18).repeatForever(autoreverses: true)) { drift = true }
        }
    }
}

// MARK: - Buttons

struct PillButtonStyle: ButtonStyle {
    enum Kind { case primary, secondary, danger }
    var kind: Kind = .primary

    func makeBody(configuration: Configuration) -> some View {
        PillBody(kind: kind, fill: fill, configuration: configuration)
    }

    private var fill: Color {
        switch kind {
        case .primary: .white
        case .secondary: .white.opacity(0.08)
        case .danger: Theme.danger.opacity(0.9)
        }
    }
}

private struct PillBody: View {
    let kind: PillButtonStyle.Kind
    let fill: Color
    let configuration: ButtonStyleConfiguration
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hover = false

    var body: some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .frame(height: 36)
            .foregroundStyle(kind == .primary ? Color.black : Color.white)
            .background {
                Capsule().fill(fill)
            }
            .overlay { Capsule().strokeBorder(.white.opacity(kind == .secondary ? 0.14 : 0), lineWidth: 1) }
            .brightness(hover && enabled ? (kind == .primary ? -0.06 : 0.06) : 0)
            .opacity(!enabled ? 0.38 : configuration.isPressed ? 0.75 : 1)
            .scaleEffect(configuration.isPressed ? 0.96 : 1)
            .animation(Motion.quick, value: configuration.isPressed)
            .animation(Motion.quick, value: hover)
            .contentShape(Capsule())
            .onHover { hover = $0 }
    }
}

extension ButtonStyle where Self == PillButtonStyle {
    static var pill: PillButtonStyle { .init() }
    static var pillSecondary: PillButtonStyle { .init(kind: .secondary) }
    static var pillDanger: PillButtonStyle { .init(kind: .danger) }
}

struct CircleIconButton: View {
    let symbol: String
    var help: String = ""
    let action: () -> Void
    @Environment(\.isEnabled) private var enabled
    @ViewState private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .medium))
                .frame(width: 38, height: 38)
                .background(Circle().fill(.white.opacity(hover && enabled ? 0.14 : 0.08)))
                .overlay(Circle().strokeBorder(.white.opacity(0.12)))
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(.white)
        .opacity(enabled ? 1 : 0.4)
        .onHover { hover = $0 }
        .animation(Motion.quick, value: hover)
        .help(help)
        .accessibilityLabel(help)
    }
}

/// A capsule segmented control in the app's style; the white pill slides to the choice.
struct PillPicker<Value: Hashable>: View {
    @Binding var selection: Value
    let options: [(String, Value)]
    @Namespace private var pill

    var body: some View {
        HStack(spacing: 2) {
            ForEach(options, id: \.1) { title, value in
                let on = selection == value
                Button { withAnimation(Motion.quick) { selection = value } } label: {
                    Text(title).font(.system(size: 12.5, weight: on ? .semibold : .regular))
                        .foregroundStyle(on ? Color.black : .white.opacity(0.75))
                        .padding(.horizontal, 14).frame(height: 30)
                        .background { if on { Capsule().fill(.white).matchedGeometryEffect(id: "pill", in: pill) } }
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .padding(4)
        .background(Capsule().fill(.white.opacity(0.07)))
        .overlay(Capsule().strokeBorder(Theme.hairline))
    }
}

/// A small rounded tag ("Would clean", "Admin", "Skipped").
struct Tag: View {
    let text: String
    var color: Color = .white

    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium))
            .padding(.horizontal, 9)
            .frame(height: 22)
            .foregroundStyle(color.opacity(0.9))
            .background(Capsule().fill(color.opacity(0.12)))
    }
}

// MARK: - Typography helpers

extension View {
    func cardTitle() -> some View {
        font(.system(size: 15, weight: .medium)).foregroundStyle(Theme.primaryText)
    }

    func caption() -> some View {
        font(.system(size: 12)).foregroundStyle(Theme.secondaryText)
    }
}

extension Int64 {
    var bytesText: String { ByteSize.format(self) }
}

/// SwiftUI's `State` property wrapper without the `@State` macro, whose plugin ships only with
/// Xcode. Command Line Tools alone can then build the app.
typealias ViewState<Value> = SwiftUI.State<Value>
