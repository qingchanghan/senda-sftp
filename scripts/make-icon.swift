import AppKit

@main
struct IconGenerator {
static func main() throws {
let output = CommandLine.arguments[1] + "/Senda.iconset"
try FileManager.default.createDirectory(atPath: output, withIntermediateDirectories: true)
for (name, pixels) in [("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64), ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512), ("icon_512x512", 512), ("icon_512x512@2x", 1024)] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState(); NSGraphicsContext.current = context
    let scale = CGFloat(pixels) / 1024
    context.cgContext.scaleBy(x: scale, y: scale)
    let rect = NSRect(x: 90, y: 90, width: 844, height: 844)
    let base = NSBezierPath(roundedRect: rect, xRadius: 190, yRadius: 190)
    NSAppearance(named: .aqua)!.performAsCurrentDrawingAppearance {
    T.inkNS.setFill(); base.fill()
    T.accentNS.setFill()
    NSBezierPath(roundedRect: NSRect(x: 217, y: 262, width: 590, height: 500), xRadius: 65, yRadius: 65).fill()
    T.surfaceNS.setStroke()
    let arrows = NSBezierPath(); arrows.lineWidth = 46; arrows.lineCapStyle = .round; arrows.lineJoinStyle = .round
    arrows.move(to: NSPoint(x: 404, y: 360)); arrows.line(to: NSPoint(x: 404, y: 666))
    arrows.move(to: NSPoint(x: 315, y: 576)); arrows.line(to: NSPoint(x: 404, y: 666)); arrows.line(to: NSPoint(x: 493, y: 576))
    arrows.move(to: NSPoint(x: 620, y: 666)); arrows.line(to: NSPoint(x: 620, y: 360))
    arrows.move(to: NSPoint(x: 531, y: 450)); arrows.line(to: NSPoint(x: 620, y: 360)); arrows.line(to: NSPoint(x: 709, y: 450)); arrows.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: output + "/" + name + ".png"))
}

}
}
