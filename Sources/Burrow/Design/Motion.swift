import SwiftUI

/// The app's motion vocabulary. Every curve falls back to a short fade when the user asked
/// macOS to reduce motion (System Settings → Accessibility → Display).
enum Motion {
    static var reduced: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    /// Entrances, page changes, layout changes.
    static var spring: Animation { reduced ? .easeInOut(duration: 0.2) : .spring(duration: 0.5, bounce: 0.14) }
    /// Hover, press and selection feedback.
    static var quick: Animation { reduced ? .easeInOut(duration: 0.12) : .spring(duration: 0.28, bounce: 0.1) }
    /// Page-to-page cross-fade: short, so navigation never feels sluggish.
    static var page: Animation { reduced ? .easeInOut(duration: 0.15) : .spring(duration: 0.38, bounce: 0.06) }
}

/// Opacity, lift and blur together: the entrance and page-change look of the app.
struct BlurFade: ViewModifier {
    let active: Bool

    func body(content: Content) -> some View {
        if Motion.reduced {
            content.opacity(active ? 0 : 1)
        } else {
            content
                .opacity(active ? 0 : 1)
                .blur(radius: active ? 8 : 0)
                .offset(y: active ? 12 : 0)
                .scaleEffect(active ? 0.99 : 1, anchor: .top)
        }
    }
}

extension AnyTransition {
    static var blurFade: AnyTransition { .modifier(active: BlurFade(active: true), identity: BlurFade(active: false)) }
}

/// Fades a view in when it first appears; views lower on screen start a little later,
/// so a page builds from top to bottom.
struct Reveal: ViewModifier {
    @ViewState private var shown = Motion.reduced
    @ViewState private var scheduled = false

    func body(content: Content) -> some View {
        content
            .modifier(BlurFade(active: !shown))
            .onGeometryChange(for: CGFloat.self, of: { $0.frame(in: .global).minY }) { y in
                guard !scheduled else { return }
                scheduled = true
                let delay = min(max((y - 120) / 2000, 0), 0.24)
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
            .scaleEffect(hover && !Motion.reduced ? scale : 1)
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
                if active && !Motion.reduced {
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
