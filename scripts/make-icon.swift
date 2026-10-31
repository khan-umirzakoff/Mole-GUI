// Draws the app icon as a 1024px PNG: the mouth of a burrow, rings stepping down into the dark,
// lit from inside, on Apple's icon grid (824pt body, continuous corners).
// Usage: swift scripts/make-icon.swift <output.png> [small]
// `small` draws the 16 and 32 px variant: fewer, wider rings that still read at that size.
import AppKit
import SwiftUI

let small = CommandLine.arguments.count > 2 && CommandLine.arguments[2] == "small"
let size: CGFloat = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255, blue: CGFloat(hex & 0xff) / 255, alpha: a)
}
func gradient(_ colors: [CGColor], _ locations: [CGFloat]? = nil) -> CGGradient {
    CGGradient(colorsSpace: space, colors: colors as CFArray, locations: locations)!
}

let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let shape = RoundedRectangle(cornerRadius: 185.4, style: .continuous).path(in: body).cgPath

// Drop shadow under the body, as on the Dock.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: rgb(0x000000, 0.4))
ctx.addPath(shape)
ctx.setFillColor(rgb(0x0B0C1E))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(shape)
ctx.clip()
// Deep indigo, lighter at the top.
ctx.drawLinearGradient(gradient([rgb(0x22265E), rgb(0x0E0F2A), rgb(0x080814)], [0, 0.6, 1]),
                       start: CGPoint(x: 512, y: body.maxY), end: CGPoint(x: 512, y: body.minY), options: [])
let floor: CGFloat = small ? 200 : 236
// Light spilling out of the burrow.
let mouth = CGPoint(x: 512, y: floor + 90)
ctx.drawRadialGradient(gradient([rgb(0x7B5CFF, 0.6), rgb(0x9A3FC0, 0.18), rgb(0x9A3FC0, 0)], [0, 0.5, 1]),
                       startCenter: mouth, startRadius: 0, endCenter: mouth, endRadius: 470, options: [])

// The burrow: arches on one floor, each smaller and darker, down to the hole.
func arch(width w: CGFloat, height h: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let r = w / 2
    p.move(to: CGPoint(x: 512 - r, y: floor))
    p.addLine(to: CGPoint(x: 512 - r, y: floor + h - r))
    p.addArc(center: CGPoint(x: 512, y: floor + h - r), radius: r, startAngle: .pi, endAngle: 0, clockwise: true)
    p.addLine(to: CGPoint(x: 512 + r, y: floor))
    p.closeSubpath()
    return p
}
let rings: [(w: CGFloat, h: CGFloat, top: UInt32, bottom: UInt32)] = small ? [
    (640, 600, 0xEFECFF, 0xC4B9FF),
    (440, 420, 0x8470F0, 0x5038C8),
] : [
    (576, 506, 0xEFECFF, 0xC4B9FF),
    (466, 420, 0xA897FF, 0x8470F0),
    (364, 340, 0x6C55E8, 0x5038C8),
    (270, 266, 0x3E2AA8, 0x2A1A7A),
]
for (i, ring) in rings.enumerated() {
    let path = arch(width: ring.w, height: ring.h)
    ctx.saveGState()
    // Each ring casts a shadow onto the next one in, which gives the depth.
    if i > 0 { ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x05040F, 0.7)) }
    ctx.addPath(path)
    ctx.setFillColor(rgb(ring.bottom))
    ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    ctx.drawLinearGradient(gradient([rgb(ring.top), rgb(ring.bottom)]),
                           start: CGPoint(x: 512, y: floor + ring.h), end: CGPoint(x: 512, y: floor), options: [])
    ctx.restoreGState()
}
// The hole: dark, with a warm light deep inside, the brightest point of the icon.
let hole = small ? arch(width: 250, height: 250) : arch(width: 182, height: 196)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: rgb(0x000000, 0.7))
ctx.addPath(hole)
ctx.setFillColor(rgb(0x07051A))
ctx.fillPath()
ctx.restoreGState()
ctx.saveGState()
ctx.addPath(hole)
ctx.clip()
let core = CGPoint(x: 512, y: floor + 36)
ctx.drawRadialGradient(gradient([rgb(0xFFB3E0, 1), rgb(0xE05FB8, 0.5), rgb(0xE05FB8, 0)], [0, 0.35, 1]),
                       startCenter: core, startRadius: 0, endCenter: core, endRadius: small ? 190 : 150, options: [])
ctx.restoreGState()

if !small {
    // The ground: a little darker, with a pool of light at the burrow's mouth.
    ctx.drawLinearGradient(gradient([rgb(0x000000, 0), rgb(0x000000, 0.3)]),
                           start: CGPoint(x: 512, y: floor), end: CGPoint(x: 512, y: body.minY), options: [])
    ctx.saveGState()
    ctx.clip(to: CGRect(x: body.minX, y: body.minY, width: body.width, height: floor - body.minY))
    ctx.translateBy(x: 512, y: floor - 6)
    ctx.scaleBy(x: 1, y: 0.18)
    ctx.drawRadialGradient(gradient([rgb(0xB07CFF, 0.45), rgb(0xB07CFF, 0)]),
                           startCenter: .zero, startRadius: 0, endCenter: .zero, endRadius: 260, options: [])
    ctx.restoreGState()
}
ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
