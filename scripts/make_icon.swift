import AppKit

// Renders the 1024px app icon: a low sun over layered swell lines.
let px = 1024
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> NSColor { NSColor(srgbRed: r, green: g, blue: b, alpha: a) }

let tile = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: tile, xRadius: 186, yRadius: 186)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowBlurRadius = 30
shadow.shadowOffset = NSSize(width: 0, height: -12)
shadow.shadowColor = rgb(0, 0, 0, 0.4)
shadow.set()
rgb(0, 0, 0).setFill()
shape.fill()
NSGraphicsContext.restoreGraphicsState()

// Dusk sky into deep ocean
NSGradient(colors: [rgb(1.0, 0.62, 0.42), rgb(0.93, 0.42, 0.52), rgb(0.33, 0.25, 0.55), rgb(0.06, 0.20, 0.42)],
           atLocations: [0, 0.32, 0.55, 1], colorSpace: .sRGB)!.draw(in: shape, angle: -90)

NSGraphicsContext.saveGraphicsState()
shape.addClip()

// Sun with glow, sitting on the horizon
let sunCenter = NSPoint(x: 512, y: 560)
NSGradient(colors: [rgb(1, 0.85, 0.55, 0.9), rgb(1, 0.6, 0.4, 0)])!
    .draw(fromCenter: sunCenter, radius: 0, toCenter: sunCenter, radius: 330, options: [])
rgb(1.0, 0.88, 0.62).setFill()
NSBezierPath(ovalIn: NSRect(x: sunCenter.x - 150, y: sunCenter.y - 150, width: 300, height: 300)).fill()

// Swell lines: each a smooth wave band, darker and bolder toward the viewer
func wave(baseY: CGFloat, amplitude: CGFloat, wavelength: CGFloat, phase: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: NSPoint(x: 80, y: 0))
    path.line(to: NSPoint(x: 80, y: baseY))
    var x: CGFloat = 80
    while x <= 944 {
        let y = baseY + amplitude * sin((x / wavelength) * 2 * .pi + phase)
        path.line(to: NSPoint(x: x, y: y))
        x += 4
    }
    path.line(to: NSPoint(x: 944, y: 0))
    path.close()
    color.setFill()
    path.fill()
}
wave(baseY: 540, amplitude: 10, wavelength: 260, phase: 0.6, color: rgb(0.20, 0.30, 0.62))
wave(baseY: 470, amplitude: 22, wavelength: 300, phase: 2.0, color: rgb(0.13, 0.36, 0.66))
wave(baseY: 385, amplitude: 34, wavelength: 360, phase: 3.6, color: rgb(0.08, 0.42, 0.70))
wave(baseY: 290, amplitude: 46, wavelength: 420, phase: 5.0, color: rgb(0.05, 0.50, 0.74))

// Foam highlights along the front wave crests
rgb(1, 1, 1, 0.85).setStroke()
for (baseY, amp, len, phase, width) in [(290.0, 46.0, 420.0, 5.0, 10.0), (385.0, 34.0, 360.0, 3.6, 7.0)] as [(CGFloat, CGFloat, CGFloat, CGFloat, CGFloat)] {
    let crest = NSBezierPath()
    crest.lineWidth = width
    crest.lineCapStyle = .round
    var first = true
    var x: CGFloat = 80
    while x <= 944 {
        let y = baseY + amp * sin((x / len) * 2 * .pi + phase)
        if first { crest.move(to: NSPoint(x: x, y: y)); first = false } else { crest.line(to: NSPoint(x: x, y: y)) }
        x += 4
    }
    crest.stroke()
}
NSGraphicsContext.restoreGraphicsState()

rgb(1, 1, 1, 0.15).setStroke()
let edge = NSBezierPath(roundedRect: tile.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
edge.lineWidth = 3
edge.stroke()

NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
