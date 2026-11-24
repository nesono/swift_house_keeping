import AppKit

/// A white house with a teal door.
func drawHouse() {
    let house = NSBezierPath()
    house.move(to: NSPoint(x: 512, y: 792))
    house.line(to: NSPoint(x: 214, y: 536))
    house.line(to: NSPoint(x: 290, y: 536))
    house.line(to: NSPoint(x: 290, y: 262))
    house.line(to: NSPoint(x: 734, y: 262))
    house.line(to: NSPoint(x: 734, y: 536))
    house.line(to: NSPoint(x: 810, y: 536))
    house.close()
    house.lineJoinStyle = .round
    house.lineWidth = 44

    // Compose the house on its own layer so the tint and door follow the outline exactly.
    let layer = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
        NSColor.white.setFill()
        NSColor.white.setStroke()
        house.fill()
        house.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        NSGradient(starting: NSColor(white: 1, alpha: 0), ending: NSColor(red: 0.62, green: 0.86, blue: 0.82, alpha: 1))!
            .draw(in: NSRect(x: 0, y: 240, width: rect.width, height: 580), angle: -90)
        return true
    }
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.35)
    shadow.shadowOffset = NSSize(width: 0, height: -18)
    shadow.shadowBlurRadius = 36
    shadow.set()
    layer.draw(in: NSRect(x: 0, y: 0, width: 1024, height: 1024))
    NSGraphicsContext.restoreGraphicsState()

    let door = NSBezierPath(roundedRect: NSRect(x: 448, y: 262, width: 128, height: 196), xRadius: 26, yRadius: 26)
    NSGradient(starting: NSColor(red: 0.12, green: 0.58, blue: 0.52, alpha: 1),
               ending: NSColor(red: 0.07, green: 0.34, blue: 0.38, alpha: 1))!.draw(in: door, angle: -90)
}

/// A four-pointed sparkle with concave sides.
func drawSparkle(center: NSPoint, radius: CGFloat) {
    let path = NSBezierPath()
    let inner = radius * 0.18
    let points = [
        NSPoint(x: center.x, y: center.y + radius), NSPoint(x: center.x + radius, y: center.y),
        NSPoint(x: center.x, y: center.y - radius), NSPoint(x: center.x - radius, y: center.y),
    ]
    let controls = [
        NSPoint(x: center.x + inner, y: center.y + inner), NSPoint(x: center.x + inner, y: center.y - inner),
        NSPoint(x: center.x - inner, y: center.y - inner), NSPoint(x: center.x - inner, y: center.y + inner),
    ]
    path.move(to: points[0])
    for index in 0 ..< 4 {
        path.curve(to: points[(index + 1) % 4], controlPoint1: controls[index], controlPoint2: controls[index])
    }
    path.close()
    NSColor(red: 1.0, green: 0.83, blue: 0.32, alpha: 1).setFill()
    path.fill()
}

/// Render the app icon (a house with sparkles on a teal tile) without a checked-in binary asset.
let output = URL(fileURLWithPath: CommandLine.arguments[1])
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0,
        )!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = NSAffineTransform()
        transform.scale(by: CGFloat(pixels) / 1024)
        transform.concat()
        let background = NSBezierPath(roundedRect: NSRect(x: 70, y: 70, width: 884, height: 884), xRadius: 195, yRadius: 195)
        NSGradient(starting: NSColor(red: 0.12, green: 0.58, blue: 0.52, alpha: 1),
                   ending: NSColor(red: 0.06, green: 0.28, blue: 0.34, alpha: 1))!.draw(in: background, angle: -90)
        drawHouse()
        drawSparkle(center: NSPoint(x: 762, y: 770), radius: 95)
        drawSparkle(center: NSPoint(x: 640, y: 880), radius: 42)
        drawSparkle(center: NSPoint(x: 868, y: 628), radius: 40)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
