import SwiftUI

/// Rounded ticks along an arc, filled up to `value` (0...1), like a wellness score dial.
struct ArcTicks: View {
    let value: Double
    var ticks = 22
    var color: Color = Theme.accent

    var body: some View {
        GeometryReader { geo in
            let r = min(geo.size.width / 2, geo.size.height) - 12
            let center = CGPoint(x: geo.size.width / 2, y: geo.size.height - 4)
            ZStack {
                ForEach(0..<ticks, id: \.self) { i in
                    let t = Double(i) / Double(ticks - 1)
                    let angle = Angle.degrees(180 + 180 * t)
                    Capsule()
                        .fill(t <= value ? color : Color.white.opacity(0.12))
                        .frame(width: 7, height: 24)
                        .rotationEffect(angle + .degrees(90))
                        .position(x: center.x + r * cos(angle.radians), y: center.y + r * sin(angle.radians))
                }
            }
        }
        .animation(Motion.reduced ? nil : .smooth(duration: 0.6), value: value)
        .accessibilityHidden(true)
    }
}

/// A row of dots that fills from the left, used as a linear meter.
struct DotMeter: View {
    let value: Double
    var count = 28
    var color: Color = .white

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<count, id: \.self) { i in
                Circle()
                    .fill(Double(i) / Double(count) < value ? color : Color.white.opacity(0.14))
                    .frame(width: 4, height: 4)
            }
        }
        .animation(Motion.reduced ? nil : .smooth(duration: 0.5), value: value)
        .accessibilityHidden(true)
    }
}

/// Thin vertical bars for short histories (network, per-core load).
struct BarSpark: View {
    let values: [Double]
    var color: Color = .white
    var maxValue: Double? = nil

    var body: some View {
        GeometryReader { geo in
            let top = max(maxValue ?? values.max() ?? 1, 0.0001)
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(Array(values.enumerated()), id: \.offset) { _, v in
                    Capsule()
                        .fill(color.opacity(0.35 + 0.65 * min(v / top, 1)))
                        .frame(height: max(3, geo.size.height * min(v / top, 1)))
                }
            }
            .frame(maxHeight: .infinity, alignment: .bottom)
        }
        .animation(Motion.reduced ? nil : .smooth(duration: 0.4), value: values)
        .accessibilityHidden(true)
    }
}

/// An app's icon from its bundle path. Icons are cached: grids redraw on every hover.
struct AppIcon: View {
    let path: String
    var size: CGFloat = 36

    nonisolated(unsafe) private static let cache = NSCache<NSString, NSImage>()

    var body: some View {
        Image(nsImage: Self.icon(path))
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .accessibilityHidden(true)
    }

    private static func icon(_ path: String) -> NSImage {
        if let hit = cache.object(forKey: path as NSString) { return hit }
        let image = NSWorkspace.shared.icon(forFile: path)
        cache.setObject(image, forKey: path as NSString)
        return image
    }
}
