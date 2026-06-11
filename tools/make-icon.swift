// Generates AppIcon.iconset: white macOS-style rounded square with ".md"
// in a black monospaced font. Run via build-app.sh or:
//   swift tools/make-icon.swift <output-dir>
import AppKit

let outputDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func renderIcon(canvas: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    // Standard macOS icon grid: 824/1024 squircle, ~185/1024 corner radius
    let inset = canvas * (1024 - 824) / 2048
    let rect = NSRect(x: inset, y: inset, width: canvas - 2 * inset, height: canvas - 2 * inset)
    let path = NSBezierPath(roundedRect: rect, xRadius: canvas * 185 / 1024, yRadius: canvas * 185 / 1024)
    NSColor.white.setFill()
    path.fill()

    let font = NSFont.monospacedSystemFont(ofSize: canvas * 0.28, weight: .semibold)
    let text = NSAttributedString(string: ".md", attributes: [.font: font, .foregroundColor: NSColor.black])
    let size = text.size()
    text.draw(at: NSPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let rep = renderIcon(canvas: CGFloat(size * scale))
        let suffix = scale == 2 ? "@2x" : ""
        let url = URL(fileURLWithPath: "\(outputDir)/icon_\(size)x\(size)\(suffix).png")
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }
}
print("Wrote \(outputDir)")
