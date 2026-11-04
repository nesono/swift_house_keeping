import AppKit

/// Render a small, native-looking icon without a checked-in binary asset.
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
        let symbol = NSImage(systemSymbolName: "sparkles.rectangle.stack.fill", accessibilityDescription: nil)!
            .withSymbolConfiguration(.init(pointSize: 450, weight: .regular))!
        symbol.lockFocus()
        NSColor.white.set()
        NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
        symbol.unlockFocus()
        symbol.draw(in: NSRect(x: 230, y: 240, width: 564, height: 544))
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        let url = output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png")
        try bitmap.representation(using: .png, properties: [:])!.write(to: url)
    }
}
