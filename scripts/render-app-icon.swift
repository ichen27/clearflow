import AppKit

// Original ClearFlow waveform, drawn directly at every icon resolution.
// Coordinates use a 1024-point canvas with standard transparent macOS icon margins.
let destination = CommandLine.arguments[1]
let pixels = Int(CommandLine.arguments[2])!
let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                             bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                             isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: bitmap)!
NSGraphicsContext.current = context
context.cgContext.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 184, yRadius: 184)
NSGraphicsContext.saveGraphicsState()
let shadow = NSShadow()
shadow.shadowColor = NSColor.black.withAlphaComponent(0.20)
shadow.shadowBlurRadius = 15
shadow.shadowOffset = NSSize(width: 0, height: -8)
shadow.set()
NSColor(calibratedRed: 0.10, green: 0.085, blue: 0.13, alpha: 1).setFill()
tile.fill()
NSGraphicsContext.restoreGraphicsState()
NSGradient(starting: NSColor(calibratedRed: 0.10, green: 0.085, blue: 0.13, alpha: 1),
           ending: NSColor(calibratedRed: 0.23, green: 0.205, blue: 0.29, alpha: 1))!.draw(in: tile, angle: 90)
NSColor.white.withAlphaComponent(0.12).setStroke()
tile.lineWidth = 2
tile.stroke()
NSColor(calibratedWhite: 0.975, alpha: 1).setFill()
let heights: [CGFloat] = [112, 230, 352, 488, 352, 230, 112]
for (index, height) in heights.enumerated() {
    let bar = NSRect(x: 253 + CGFloat(index) * 78, y: 512 - height / 2, width: 50, height: height)
    NSBezierPath(roundedRect: bar, xRadius: 25, yRadius: 25).fill()
}
NSGraphicsContext.restoreGraphicsState()
try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination))
