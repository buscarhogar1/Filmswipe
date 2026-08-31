import AppKit
import Foundation

struct IconSize {
    let folder: String
    let pixels: Int
}

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let outputRoot = root.appendingPathComponent("android/app/src/main/res")
let sizes = [
    IconSize(folder: "mipmap-mdpi", pixels: 48),
    IconSize(folder: "mipmap-hdpi", pixels: 72),
    IconSize(folder: "mipmap-xhdpi", pixels: 96),
    IconSize(folder: "mipmap-xxhdpi", pixels: 144),
    IconSize(folder: "mipmap-xxxhdpi", pixels: 192),
]
let launchLogoSizes = [
    IconSize(folder: "mipmap-mdpi", pixels: 160),
    IconSize(folder: "mipmap-hdpi", pixels: 240),
    IconSize(folder: "mipmap-xhdpi", pixels: 320),
    IconSize(folder: "mipmap-xxhdpi", pixels: 480),
    IconSize(folder: "mipmap-xxxhdpi", pixels: 640),
]

extension NSColor {
    convenience init(hex: UInt32) {
        self.init(
            calibratedRed: CGFloat((hex >> 16) & 0xff) / 255,
            green: CGFloat((hex >> 8) & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255,
            alpha: 1
        )
    }
}

func drawRoundedCard(in rect: NSRect, radius: CGFloat, angle: CGFloat, fill: NSColor, shadowAlpha: CGFloat) {
    let center = NSPoint(x: rect.midX, y: rect.midY)
    NSGraphicsContext.current?.cgContext.saveGState()
    NSGraphicsContext.current?.cgContext.translateBy(x: center.x, y: center.y)
    NSGraphicsContext.current?.cgContext.rotate(by: angle * .pi / 180)
    NSGraphicsContext.current?.cgContext.translateBy(x: -center.x, y: -center.y)

    let shadow = NSShadow()
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.08)
    shadow.shadowBlurRadius = rect.width * 0.18
    shadow.shadowColor = NSColor.black.withAlphaComponent(shadowAlpha)
    shadow.set()

    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
    NSGraphicsContext.current?.cgContext.restoreGState()
}

func drawChevron(from start: NSPoint, mid: NSPoint, end: NSPoint, width: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.move(to: start)
    path.line(to: mid)
    path.line(to: end)
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    path.lineWidth = width
    color.setStroke()
    path.stroke()
}

func renderIcon(size: Int) throws -> Data {
    let dimension = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "FilmswipeIcon", code: 1)
    }

    bitmap.size = NSSize(width: dimension, height: dimension)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()

    let backgroundInset = dimension * 0.035
    let backgroundRect = NSRect(
        x: backgroundInset,
        y: backgroundInset,
        width: dimension - backgroundInset * 2,
        height: dimension - backgroundInset * 2
    )
    let backgroundPath = NSBezierPath(
        roundedRect: backgroundRect,
        xRadius: dimension * 0.215,
        yRadius: dimension * 0.215
    )
    NSColor(hex: 0xf4a124).setFill()
    backgroundPath.fill()

    let cardWidth = dimension * 0.36
    let cardHeight = dimension * 0.53
    let cardY = dimension * 0.22
    let backRect = NSRect(
        x: dimension * 0.28,
        y: cardY,
        width: cardWidth,
        height: cardHeight
    )
    let frontRect = NSRect(
        x: dimension * 0.41,
        y: cardY,
        width: cardWidth,
        height: cardHeight
    )
    let radius = dimension * 0.085

    drawRoundedCard(
        in: backRect,
        radius: radius,
        angle: -11,
        fill: NSColor(hex: 0xf4efe7),
        shadowAlpha: 0.25
    )
    drawRoundedCard(
        in: frontRect,
        radius: radius,
        angle: 10,
        fill: NSColor(hex: 0x211e1a),
        shadowAlpha: 0.34
    )

    let arrowScale = dimension / 192
    NSGraphicsContext.current?.cgContext.saveGState()
    NSGraphicsContext.current?.cgContext.translateBy(x: frontRect.midX, y: frontRect.midY)
    NSGraphicsContext.current?.cgContext.rotate(by: 10 * .pi / 180)
    NSGraphicsContext.current?.cgContext.translateBy(x: -frontRect.midX, y: -frontRect.midY)
    let lineWidth = max(2.2, 6.8 * arrowScale)
    let x = frontRect.midX - 9 * arrowScale
    let y = frontRect.midY
    let step = 12 * arrowScale
    let rise = 15 * arrowScale
    drawChevron(
        from: NSPoint(x: x - step, y: y - rise),
        mid: NSPoint(x: x, y: y),
        end: NSPoint(x: x - step, y: y + rise),
        width: lineWidth,
        color: NSColor(hex: 0xf4a124)
    )
    drawChevron(
        from: NSPoint(x: x + 10 * arrowScale, y: y - rise),
        mid: NSPoint(x: x + step + 10 * arrowScale, y: y),
        end: NSPoint(x: x + 10 * arrowScale, y: y + rise),
        width: lineWidth,
        color: NSColor(hex: 0xf4a124)
    )
    NSGraphicsContext.current?.cgContext.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "FilmswipeIcon", code: 2)
    }
    return png
}

func renderLaunchLogo(size: Int) throws -> Data {
    let dimension = CGFloat(size)
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: size,
        pixelsHigh: size,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw NSError(domain: "FilmswipeSplashLogo", code: 1)
    }

    bitmap.size = NSSize(width: dimension, height: dimension)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.setShouldAntialias(true)

    NSColor.clear.setFill()
    NSRect(x: 0, y: 0, width: dimension, height: dimension).fill()

    // Android 12+ crops splash icons to a circular safe area. At 0.50 the
    // rotated cards, including their shadows, stay inside that mask on cold
    // starts instead of having their corners clipped.
    let artScale: CGFloat = 0.50
    let artSize = dimension * artScale
    let artInset = (dimension - artSize) / 2

    let backRect = NSRect(
        x: artInset + artSize * 0.08,
        y: artInset + artSize * 0.17,
        width: artSize * 0.52,
        height: artSize * 0.64
    )
    let frontRect = NSRect(
        x: artInset + artSize * 0.35,
        y: artInset + artSize * 0.12,
        width: artSize * 0.54,
        height: artSize * 0.70
    )
    let radius = artSize * 0.105

    drawRoundedCard(
        in: backRect,
        radius: radius,
        angle: -11,
        fill: NSColor(hex: 0xf4efe7),
        shadowAlpha: 0.18
    )
    drawRoundedCard(
        in: frontRect,
        radius: radius,
        angle: 9,
        fill: NSColor(hex: 0xf4a124),
        shadowAlpha: 0.16
    )

    let arrowScale = artSize / 640
    NSGraphicsContext.current?.cgContext.saveGState()
    NSGraphicsContext.current?.cgContext.translateBy(x: frontRect.midX, y: frontRect.midY)
    NSGraphicsContext.current?.cgContext.rotate(by: 9 * .pi / 180)
    NSGraphicsContext.current?.cgContext.translateBy(x: -frontRect.midX, y: -frontRect.midY)
    let lineWidth = max(5.0, 28 * arrowScale)
    let x = frontRect.midX - 22 * arrowScale
    let y = frontRect.midY
    let step = 54 * arrowScale
    let rise = 68 * arrowScale
    drawChevron(
        from: NSPoint(x: x - step, y: y - rise),
        mid: NSPoint(x: x, y: y),
        end: NSPoint(x: x - step, y: y + rise),
        width: lineWidth,
        color: NSColor(hex: 0x211e1a)
    )
    drawChevron(
        from: NSPoint(x: x + 44 * arrowScale, y: y - rise),
        mid: NSPoint(x: x + step + 44 * arrowScale, y: y),
        end: NSPoint(x: x + 44 * arrowScale, y: y + rise),
        width: lineWidth,
        color: NSColor(hex: 0x211e1a)
    )
    NSGraphicsContext.current?.cgContext.restoreGState()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        throw NSError(domain: "FilmswipeSplashLogo", code: 2)
    }
    return png
}

for icon in sizes {
    let folder = outputRoot.appendingPathComponent(icon.folder, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let png = try renderIcon(size: icon.pixels)
    try png.write(to: folder.appendingPathComponent("ic_launcher.png"))
    print("Wrote \(icon.folder)/ic_launcher.png")
}

for logo in launchLogoSizes {
    let folder = outputRoot.appendingPathComponent(logo.folder, isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let png = try renderLaunchLogo(size: logo.pixels)
    try png.write(to: folder.appendingPathComponent("launch_logo.png"))
    print("Wrote \(logo.folder)/launch_logo.png")
}
