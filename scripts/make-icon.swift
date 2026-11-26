import AppKit

// Render the app icon (a house with sparkles on a macOS-style tile) without a checked-in binary asset.
// Follows the macOS icon grid: an 824 pt squircle centered in a 1024 pt canvas, with a soft drop shadow.

let canvas: CGFloat = 1024
let tileRect = NSRect(x: 100, y: 100, width: 824, height: 824)

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(red: red, green: green, blue: blue, alpha: alpha)
}

/// A superellipse approximates the continuous-corner squircle used by macOS icons.
func squircle(in rect: NSRect, exponent: CGFloat = 4) -> NSBezierPath {
    let path = NSBezierPath()
    let steps = 360
    for step in 0 ... steps {
        let angle = CGFloat(step) / CGFloat(steps) * 2 * .pi
        let cosine = cos(angle)
        let sine = sin(angle)
        let x = rect.midX + rect.width / 2 * (cosine < 0 ? -1 : 1) * pow(abs(cosine), 2 / exponent)
        let y = rect.midY + rect.height / 2 * (sine < 0 ? -1 : 1) * pow(abs(sine), 2 / exponent)
        if step == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
    }
    path.close()
    return path
}

func drawTile() {
    let tile = squircle(in: tileRect)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor(white: 0, alpha: 0.32)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 28
    shadow.set()
    color(0.05, 0.42, 0.80).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGraphicsContext.saveGraphicsState()
    tile.addClip()
    NSGradient(starting: color(0.30, 0.82, 0.93), ending: color(0.06, 0.40, 0.84))!.draw(in: tileRect, angle: -90)
    // Soft light from above, as on system app icons.
    NSGradient(starting: NSColor(white: 1, alpha: 0.28), ending: NSColor(white: 1, alpha: 0))!
        .draw(in: NSRect(x: tileRect.minX, y: tileRect.midY, width: tileRect.width, height: tileRect.height / 2), angle: -90)
    // Thin inner highlight along the edge.
    NSColor(white: 1, alpha: 0.35).setStroke()
    tile.lineWidth = 4
    tile.stroke()
    NSGraphicsContext.restoreGraphicsState()
}

func houseOutline() -> NSBezierPath {
    let house = NSBezierPath()
    house.move(to: NSPoint(x: 512, y: 772))
    house.line(to: NSPoint(x: 232, y: 540))
    house.line(to: NSPoint(x: 296, y: 540))
    house.line(to: NSPoint(x: 296, y: 290))
    house.line(to: NSPoint(x: 728, y: 290))
    house.line(to: NSPoint(x: 728, y: 540))
    house.line(to: NSPoint(x: 792, y: 540))
    house.close()
    house.append(NSBezierPath(rect: NSRect(x: 330, y: 620, width: 64, height: 130)))
    house.lineJoinStyle = .round
    house.lineWidth = 48
    return house
}

func drawHouse() {
    let house = houseOutline()
    let layer = NSImage(size: NSSize(width: canvas, height: canvas), flipped: false) { rect in
        NSColor.white.setFill()
        NSColor.white.setStroke()
        house.fill()
        house.stroke()
        NSGraphicsContext.current?.compositingOperation = .sourceAtop
        NSGradient(starting: color(1, 1, 1), ending: color(0.78, 0.90, 0.98))!
            .draw(in: NSRect(x: 0, y: 260, width: rect.width, height: 540), angle: -90)
        return true
    }

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = color(0.0, 0.18, 0.45, 0.45)
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.shadowBlurRadius = 26
    shadow.set()
    layer.draw(in: NSRect(x: 0, y: 0, width: canvas, height: canvas))
    NSGraphicsContext.restoreGraphicsState()

    // Arched door.
    let door = NSBezierPath()
    door.move(to: NSPoint(x: 448, y: 266))
    door.line(to: NSPoint(x: 448, y: 410))
    door.appendArc(withCenter: NSPoint(x: 512, y: 410), radius: 64, startAngle: 180, endAngle: 0, clockwise: true)
    door.line(to: NSPoint(x: 576, y: 266))
    door.close()
    NSGradient(starting: color(0.20, 0.62, 0.92), ending: color(0.06, 0.40, 0.84))!.draw(in: door, angle: -90)
}

/// A four-pointed sparkle with concave sides and a warm glow.
func drawSparkle(center: NSPoint, radius: CGFloat) {
    let path = NSBezierPath()
    let inner = radius * 0.16
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

    NSGraphicsContext.saveGraphicsState()
    let glow = NSShadow()
    glow.shadowColor = color(1.0, 0.85, 0.35, 0.8)
    glow.shadowOffset = .zero
    glow.shadowBlurRadius = radius * 0.5
    glow.set()
    NSGradient(starting: color(1.0, 0.96, 0.62), ending: color(1.0, 0.76, 0.22))!.draw(in: path, angle: -90)
    NSGraphicsContext.restoreGraphicsState()
}

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
        transform.scale(by: CGFloat(pixels) / canvas)
        transform.concat()
        drawTile()
        drawHouse()
        drawSparkle(center: NSPoint(x: 724, y: 770), radius: 96)
        drawSparkle(center: NSPoint(x: 614, y: 850), radius: 40)
        drawSparkle(center: NSPoint(x: 838, y: 632), radius: 38)
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
