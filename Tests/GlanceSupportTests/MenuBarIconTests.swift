import AppKit
import Testing
@testable import GlanceSupport

@Test(arguments: [1.0, 2.0])
@MainActor
func menuBarIconRetainsTintAtDifferentScales(scale: Double) throws {
    let image = makeIcon(symbolName: "circle.fill", color: .red)
    #expect(!image.isTemplate)
    let width = Int(ceil(image.size.width * scale))
    let height = Int(ceil(image.size.height * scale))
    let bitmap = try #require(NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: width,
        pixelsHigh: height,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ))
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: scale, y: scale)
    image.draw(in: NSRect(origin: .zero, size: image.size))
    let center = try #require(bitmap.colorAt(x: width / 2, y: height / 2)?.usingColorSpace(.deviceRGB))
    #expect(center.redComponent > 0.9)
    #expect(center.greenComponent < 0.1)
    #expect(center.blueComponent < 0.1)
    #expect(center.alphaComponent > 0.9)
}
