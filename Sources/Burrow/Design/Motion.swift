import SwiftUI

enum Motion {
    static let spring = Animation.spring(duration: 0.55, bounce: 0.18)
    static let quick = Animation.spring(duration: 0.3, bounce: 0.12)
}

/// Opacity, lift and blur together: the entrance and page-change look of the app.
struct BlurFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        content
            .opacity(active ? 0 : 1)
            .blur(radius: active ? 10 : 0)
            .offset(y: active ? 16 : 0)
            .scaleEffect(active ? 0.985 : 1, anchor: .top)
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition { .modifier(active: BlurFade(active: true), identity: BlurFade(active: false)) }
}

/// Fades a view in when it first appears; views lower on screen start a little later,
/// so a page builds from top to bottom.
struct Reveal: ViewModifier {
    @ViewState private var shown = false
    @ViewState private var scheduled = false

    func body(content: Content) -> some View {
        content
            .modifier(BlurFade(active: !shown))
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { y in
                guard !scheduled else { return }
                scheduled = true
                let delay = min(max((y - 120) / 1600, 0), 0.32)
                withAnimation(Motion.spring.delay(delay)) { shown = true }
            }
    }
}

/// A gentle lift and glow on hover for anything clickable.
struct HoverLift: ViewModifier {
    @ViewState private var hover = false
    var scale: CGFloat = 1.015

    func body(content: Content) -> some View {
        content
            .scaleEffect(hover ? scale : 1)
            .brightness(hover ? 0.04 : 0)
            .animation(Motion.quick, value: hover)
            .onHover { hover = $0 }
    }
}

/// A light band sweeping across while something is in progress.
struct Shimmer: ViewModifier {
    var active: Bool
    @ViewState private var phase: CGFloat = -1

    func body(content: Content) -> some View {
        content
            .overlay {
                if active {
                    GeometryReader { geo in
                        LinearGradient(colors: [.clear, .white.opacity(0.35), .clear], startPoint: .leading, endPoint: .trailing)
                            .frame(width: geo.size.width * 0.45)
                            .offset(x: phase * geo.size.width * 1.4)
                            .blendMode(.plusLighter)
                    }
                    .mask(content)
                    .onAppear {
                        phase = -0.6
                        withAnimation(.linear(duration: 1.6).repeatForever(autoreverses: false)) { phase = 1 }
                    }
                }
            }
    }
}

extension View {
    func reveal() -> some View { modifier(Reveal()) }
    func hoverLift(_ scale: CGFloat = 1.015) -> some View { modifier(HoverLift(scale: scale)) }
    func shimmer(_ active: Bool = true) -> some View { modifier(Shimmer(active: active)) }
}
