// Generates Resources/AppIcon.icns. Usage: swift scripts/make-icon.swift <output.icns>
import AppKit

func render(pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.current = context
    context.imageInterpolation = .high
    let s = CGFloat(pixels) / 1024.0

    let rect = NSRect(x: 64 * s, y: 64 * s, width: 896 * s, height: 896 * s)
    let background = NSBezierPath(roundedRect: rect, xRadius: 200 * s, yRadius: 200 * s)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.98, green: 0.52, blue: 0.16, alpha: 1),
        NSColor(calibratedRed: 0.82, green: 0.27, blue: 0.07, alpha: 1),
    ])!
    gradient.draw(in: background, angle: -70)

    // "CR" letters
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let attributes: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 360 * s, weight: .black),
        .foregroundColor: NSColor.white,
        .paragraphStyle: paragraph,
    ]
    ("CR" as NSString).draw(in: NSRect(x: 0, y: 470 * s, width: 1024 * s, height: 400 * s), withAttributes: attributes)

    // Subtitle bars
    NSColor.white.withAlphaComponent(0.95).setFill()
    NSBezierPath(roundedRect: NSRect(x: 190 * s, y: 330 * s, width: 644 * s, height: 78 * s), xRadius: 39 * s, yRadius: 39 * s).fill()
    NSBezierPath(roundedRect: NSRect(x: 300 * s, y: 205 * s, width: 424 * s, height: 78 * s), xRadius: 39 * s, yRadius: 39 * s).fill()

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

let arguments = CommandLine.arguments
guard arguments.count >= 2 else {
    FileHandle.standardError.write("usage: make-icon <output.icns>\n".data(using: .utf8)!)
    exit(1)
}
let output = URL(fileURLWithPath: arguments[1])
let iconset = output.deletingLastPathComponent().appendingPathComponent("AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconset)
try! FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

let sizes: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32), ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256), ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, pixels) in sizes {
    let rep = render(pixels: pixels)
    let data = rep.representation(using: .png, properties: [:])!
    try! data.write(to: iconset.appendingPathComponent("\(name).png"))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", output.path]
try! iconutil.run()
iconutil.waitUntilExit()
try? FileManager.default.removeItem(at: iconset)
print(iconutil.terminationStatus == 0 ? "wrote \(output.path)" : "iconutil failed")
exit(iconutil.terminationStatus)
