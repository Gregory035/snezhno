import AppKit

let size = 1024
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                              bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                              colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
let tile = NSBezierPath(roundedRect: NSRect(x: 76, y: 76, width: 872, height: 872), xRadius: 201, yRadius: 201)
let gradient = NSGradient(starting: NSColor(srgbRed: 0.08, green: 0.14, blue: 0.29, alpha: 1),
                          ending: NSColor(srgbRed: 0.32, green: 0.52, blue: 0.82, alpha: 1))!
gradient.draw(in: tile, angle: 125)
NSColor.white.withAlphaComponent(0.24).setStroke()
tile.lineWidth = 5
tile.stroke()

tile.addClip()
let drift = NSBezierPath()
drift.move(to: NSPoint(x: 76, y: 281))
drift.curve(to: NSPoint(x: 521, y: 236), controlPoint1: NSPoint(x: 219, y: 338),
            controlPoint2: NSPoint(x: 344, y: 221))
drift.curve(to: NSPoint(x: 948, y: 283), controlPoint1: NSPoint(x: 675, y: 252),
            controlPoint2: NSPoint(x: 820, y: 327))
drift.line(to: NSPoint(x: 948, y: 76))
drift.line(to: NSPoint(x: 76, y: 76))
drift.close()
NSGradient(starting: NSColor(srgbRed: 0.43, green: 0.66, blue: 0.89, alpha: 1),
           ending: NSColor(srgbRed: 0.90, green: 0.96, blue: 1, alpha: 1))!.draw(in: drift, angle: 90)

let flakes = NSBezierPath()
flakes.lineWidth = 24
flakes.lineCapStyle = .round
let center = NSPoint(x: 512, y: 545)
for index in 0..<6 {
    let angle = CGFloat(index) * .pi / 3 + .pi / 2
    let direction = CGPoint(x: cos(angle), y: sin(angle))
    func point(_ distance: CGFloat, side: CGFloat = 0) -> CGPoint {
        CGPoint(x: center.x + direction.x * distance - direction.y * side,
                y: center.y + direction.y * distance + direction.x * side)
    }
    flakes.move(to: center)
    flakes.line(to: point(213))
    flakes.move(to: point(193, side: -56))
    flakes.line(to: point(140))
    flakes.line(to: point(193, side: 56))
}
NSColor(srgbRed: 0.93, green: 0.98, blue: 1, alpha: 1).setStroke()
flakes.stroke()

for (x, y, radius) in [(261.0, 689.0, 7.0), (763, 720, 11), (792, 472, 6), (230, 418, 9), (360, 805, 6)] {
    NSColor.white.withAlphaComponent(0.58).setFill()
    NSBezierPath(ovalIn: NSRect(x: x - radius, y: y - radius, width: radius * 2, height: radius * 2)).fill()
}

NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
