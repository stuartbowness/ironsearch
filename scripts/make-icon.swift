import AppKit

// Vector-drawn artwork keeps the small icon sizes sharp and is reproducible.
let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let iconset = root.appendingPathComponent(".build/AppIcon.iconset")
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

func render(size: Int) -> Data {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    context.cgContext.scaleBy(x: CGFloat(size) / 1024, y: CGFloat(size) / 1024)

    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824),
                            xRadius: 186, yRadius: 186)
    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
    shadow.shadowBlurRadius = 30
    shadow.shadowOffset = NSSize(width: 0, height: -14)
    shadow.set()
    NSColor(calibratedRed: 0.15, green: 0.23, blue: 0.32, alpha: 1).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSGradient(starting: NSColor(calibratedRed: 0.13, green: 0.22, blue: 0.33, alpha: 1),
               ending: NSColor(calibratedRed: 0.42, green: 0.57, blue: 0.68, alpha: 1))!
        .draw(in: tile, angle: 90)
    NSColor.white.withAlphaComponent(0.32).setStroke()
    tile.lineWidth = 3
    tile.stroke()

    // A glass lens and a bold search silhouette that reads at Dock size.
    let lens = NSBezierPath(ovalIn: NSRect(x: 278, y: 392, width: 350, height: 350))
    NSGradient(starting: NSColor.white.withAlphaComponent(0.025),
               ending: NSColor.white.withAlphaComponent(0.22))!.draw(in: lens, angle: 90)

    NSGraphicsContext.saveGraphicsState()
    let glyphShadow = NSShadow()
    glyphShadow.shadowColor = NSColor.black.withAlphaComponent(0.25)
    glyphShadow.shadowBlurRadius = 16
    glyphShadow.shadowOffset = NSSize(width: 0, height: -8)
    glyphShadow.set()
    let handle = NSBezierPath()
    handle.move(to: NSPoint(x: 591, y: 429))
    handle.line(to: NSPoint(x: 727, y: 293))
    handle.lineWidth = 66
    handle.lineCapStyle = .round
    NSColor(calibratedWhite: 0.96, alpha: 1).setStroke()
    handle.stroke()
    lens.lineWidth = 58
    lens.stroke()
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    return bitmap.representation(using: .png, properties: [:])!
}

for points in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let suffix = scale == 2 ? "@2x" : ""
        let data = render(size: points * scale)
        try data.write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"))
        if points == 512 && scale == 2 {
            try data.write(to: root.appendingPathComponent("Resources/AppIcon.png"))
        }
    }
}
