import AppKit
import Foundation

struct IconGenerationError: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@MainActor
func color(_ hex: UInt32, alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 255) / 255,
        green: CGFloat((hex >> 8) & 255) / 255,
        blue: CGFloat(hex & 255) / 255,
        alpha: alpha
    )
}

@MainActor
func rounded(_ rect: NSRect, radius: CGFloat, fill: NSColor) {
    fill.setFill()
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill()
}

@MainActor
func line(_ points: [NSPoint], color: NSColor, width: CGFloat) {
    guard let first = points.first else { return }
    let path = NSBezierPath()
    path.move(to: first)
    for point in points.dropFirst() { path.line(to: point) }
    path.lineWidth = width
    path.lineCapStyle = .round
    path.lineJoinStyle = .round
    color.setStroke()
    path.stroke()
}

@MainActor
func render(size: Int, monitor: Bool) throws -> Data {
    guard let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
        isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
        throw IconGenerationError(message: "Could not create icon drawing context")
    }
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(size) / 1_024, y: CGFloat(size) / 1_024)
    context.shouldAntialias = true
    let tile = NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 180, yRadius: 180)
    guard let gradient = NSGradient(
        starting: color(monitor ? 0x16465F : 0x393568),
        ending: color(0x101D35)
    ) else { throw IconGenerationError(message: "Could not create icon gradient") }
    gradient.draw(in: tile, angle: -90)
    if monitor {
        rounded(NSRect(x: 274, y: 342, width: 108, height: 390), radius: 54, fill: color(0xF5F7FC))
        color(0xF5F7FC).setFill()
        NSBezierPath(ovalIn: NSRect(x: 232, y: 266, width: 192, height: 192)).fill()
        rounded(NSRect(x: 309, y: 350, width: 38, height: 296), radius: 19, fill: color(0xF57867))
        color(0xF57867).setFill()
        NSBezierPath(ovalIn: NSRect(x: 268, y: 302, width: 120, height: 120)).fill()
        rounded(NSRect(x: 504, y: 300, width: 270, height: 400), radius: 36, fill: color(0x3CD9C1))
        rounded(NSRect(x: 531, y: 327, width: 216, height: 346), radius: 20, fill: color(0x123A50))
        for index in 0..<4 {
            let x = CGFloat(538 + index * 64)
            line([NSPoint(x: x, y: 286), NSPoint(x: x, y: 263)], color: color(0x3CD9C1), width: 22)
            line([NSPoint(x: x, y: 714), NSPoint(x: x, y: 737)], color: color(0x3CD9C1), width: 22)
        }
        line([
            NSPoint(x: 555, y: 490), NSPoint(x: 591, y: 490), NSPoint(x: 624, y: 553),
            NSPoint(x: 662, y: 430), NSPoint(x: 694, y: 490), NSPoint(x: 725, y: 490)
        ], color: .white, width: 24)
    } else {
        rounded(NSRect(x: 225, y: 220, width: 574, height: 574), radius: 54, fill: color(0xF5F7FC))
        rounded(NSRect(x: 225, y: 650, width: 574, height: 144), radius: 54, fill: color(0xA69BED))
        rounded(NSRect(x: 225, y: 650, width: 574, height: 70), radius: 0, fill: color(0xA69BED))
        for x in [CGFloat(350), 674] {
            line([NSPoint(x: x, y: 744), NSPoint(x: x, y: 832)], color: color(0xE2E5FB), width: 30)
        }
        for x in [CGFloat(322), 426, 530] {
            for y in [CGFloat(482), 574] {
                rounded(NSRect(x: x, y: y, width: 45, height: 36), radius: 9, fill: color(0xBBC7E4))
            }
        }
        color(0x133A51).setFill()
        NSBezierPath(ovalIn: NSRect(x: 485, y: 185, width: 340, height: 340)).fill()
        color(0x3CD9C1).setFill()
        NSBezierPath(ovalIn: NSRect(x: 508, y: 208, width: 294, height: 294)).fill()
        line([NSPoint(x: 655, y: 439), NSPoint(x: 655, y: 355), NSPoint(x: 718, y: 316)], color: color(0x133A51), width: 25)
    }
    guard let data = bitmap.representation(using: .png, properties: [:]) else {
        throw IconGenerationError(message: "Could not encode generated icon")
    }
    return data
}

let manager = FileManager.default
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let assets = root.appendingPathComponent("Assets", isDirectory: true)
let temporary = manager.temporaryDirectory.appendingPathComponent("glance-icons-\(UUID().uuidString)", isDirectory: true)
try manager.createDirectory(at: assets, withIntermediateDirectories: true)
try manager.createDirectory(at: temporary, withIntermediateDirectories: false)
defer {
    do { try manager.removeItem(at: temporary) } catch {
        FileHandle.standardError.write(Data("Icon fixture cleanup failed: \(error)\n".utf8))
    }
}
for product in ["GlanceMonitor", "GlanceTime"] {
    let iconset = temporary.appendingPathComponent("\(product).iconset", isDirectory: true)
    try manager.createDirectory(at: iconset, withIntermediateDirectories: false)
    for points in [16, 32, 128, 256, 512] {
        for scale in [1, 2] {
            let suffix = scale == 2 ? "@2x" : ""
            try render(size: points * scale, monitor: product == "GlanceMonitor")
                .write(to: iconset.appendingPathComponent("icon_\(points)x\(points)\(suffix).png"), options: .atomic)
        }
    }
    try render(size: 1_024, monitor: product == "GlanceMonitor")
        .write(to: assets.appendingPathComponent("\(product).png"), options: .atomic)
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["--convert", "icns", "--output", assets.appendingPathComponent("\(product).icns").path, iconset.path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        throw IconGenerationError(message: "iconutil failed for \(product)")
    }
}
print("Generated original Glance Monitor and Time app icons.")
