// Draws the app icon (a glowing orb on a dark, dotted squircle) as a 1024px PNG.
// Usage: swift scripts/make-icon.swift <output.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let space = CGColorSpaceCreateDeviceRGB()

// Squircle body with the macOS icon margin.
let inset: CGFloat = 100
let body = CGRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
let shape = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.addPath(shape)
ctx.clip()
ctx.setFillColor(CGColor(red: 0.03, green: 0.03, blue: 0.05, alpha: 1))
ctx.fill(body)

func glow(_ center: CGPoint, _ radius: CGFloat, _ colors: [CGColor]) {
    let g = CGGradient(colorsSpace: space, colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

// Ambient colour from the lower right, like the cards.
glow(CGPoint(x: 700, y: 260), 520, [CGColor(red: 0.25, green: 0.38, blue: 1, alpha: 0.9), CGColor(red: 0.25, green: 0.38, blue: 1, alpha: 0)])
glow(CGPoint(x: 300, y: 780), 420, [CGColor(red: 0.86, green: 0.27, blue: 0.62, alpha: 0.55), CGColor(red: 0.86, green: 0.27, blue: 0.62, alpha: 0)])

// Dot grid.
ctx.setFillColor(CGColor(gray: 1, alpha: 0.10))
var y = body.minY + 24
while y < body.maxY {
    var x = body.minX + 24
    while x < body.maxX { ctx.fillEllipse(in: CGRect(x: x, y: y, width: 7, height: 7)); x += 40 }
    y += 40
}

// The orb.
let orb = CGPoint(x: 512, y: 540)
glow(orb, 300, [CGColor(red: 0.55, green: 0.38, blue: 0.98, alpha: 0.65), CGColor(red: 0.55, green: 0.38, blue: 0.98, alpha: 0)])
ctx.saveGState()
ctx.addEllipse(in: CGRect(x: orb.x - 190, y: orb.y - 190, width: 380, height: 380))
ctx.clip()
let g = CGGradient(colorsSpace: space, colors: [
    CGColor(red: 1, green: 0.92, blue: 0.97, alpha: 1),
    CGColor(red: 0.86, green: 0.27, blue: 0.62, alpha: 1),
    CGColor(red: 0.42, green: 0.30, blue: 0.95, alpha: 1),
    CGColor(red: 0.12, green: 0.16, blue: 0.55, alpha: 1),
] as CFArray, locations: [0, 0.35, 0.7, 1])!
ctx.drawRadialGradient(g, startCenter: CGPoint(x: orb.x - 70, y: orb.y + 80), startRadius: 0,
                       endCenter: orb, endRadius: 200, options: [.drawsAfterEndLocation])
ctx.restoreGState()
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.45))
ctx.setLineWidth(4)
ctx.strokeEllipse(in: CGRect(x: orb.x - 190, y: orb.y - 190, width: 380, height: 380))

// A dotted "burrow" under the orb.
ctx.setFillColor(CGColor(red: 0.84, green: 0.96, blue: 0.35, alpha: 1))
for i in 0..<9 {
    let x = 352 + CGFloat(i) * 40
    let dip = sin(CGFloat(i) / 8 * .pi) * 40
    ctx.fillEllipse(in: CGRect(x: x - 9, y: 250 - dip - 9, width: 18, height: 18))
}

// Top highlight on the squircle edge.
ctx.resetClip()
ctx.addPath(shape)
ctx.setStrokeColor(CGColor(gray: 1, alpha: 0.16))
ctx.setLineWidth(5)
ctx.strokePath()
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
