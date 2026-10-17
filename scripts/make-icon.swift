// Draws the Wiki Explorer app icon (an open book on warm paper with a copper link mark) into an .iconset.
//   swift scripts/make-icon.swift build/AppIcon.iconset
import AppKit

let out = URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset")
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func draw(size: CGFloat) -> Data {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let s = size / 1024
    let rect = NSRect(x: 100 * s, y: 100 * s, width: 824 * s, height: 824 * s)
    let bg = NSBezierPath(roundedRect: rect, xRadius: 185 * s, yRadius: 185 * s)
    NSGradient(starting: NSColor(red: 0.98, green: 0.96, blue: 0.92, alpha: 1), ending: NSColor(red: 0.93, green: 0.89, blue: 0.82, alpha: 1))!.draw(in: bg, angle: -90)
    let ink = NSColor(red: 0.11, green: 0.12, blue: 0.13, alpha: 1)
    let copper = NSColor(red: 0.78, green: 0.38, blue: 0.23, alpha: 1)
    // Open book: two pages.
    for (dx, flip) in [(CGFloat(0), CGFloat(1)), (CGFloat(0), CGFloat(-1))] {
        let p = NSBezierPath()
        let cx = 512 * s + dx
        p.move(to: NSPoint(x: cx, y: 330 * s))
        p.curve(to: NSPoint(x: cx + flip * 300 * s, y: 360 * s), controlPoint1: NSPoint(x: cx + flip * 90 * s, y: 300 * s), controlPoint2: NSPoint(x: cx + flip * 220 * s, y: 330 * s))
        p.line(to: NSPoint(x: cx + flip * 300 * s, y: 700 * s))
        p.curve(to: NSPoint(x: cx, y: 680 * s), controlPoint1: NSPoint(x: cx + flip * 220 * s, y: 690 * s), controlPoint2: NSPoint(x: cx + flip * 90 * s, y: 650 * s))
        p.close()
        NSColor.white.setFill(); p.fill()
        ink.setStroke(); p.lineWidth = 22 * s; p.lineJoinStyle = .round; p.stroke()
    }
    // Text lines on the pages.
    ink.withAlphaComponent(0.35).setStroke()
    for i in 0..<4 {
        let y = (600 - CGFloat(i) * 62) * s
        for flip in [CGFloat(1), CGFloat(-1)] {
            let l = NSBezierPath()
            l.move(to: NSPoint(x: 512 * s + flip * 70 * s, y: y))
            l.line(to: NSPoint(x: 512 * s + flip * 240 * s, y: y + 8 * s))
            l.lineWidth = 16 * s; l.lineCapStyle = .round; l.stroke()
        }
    }
    // Copper link mark (two rings).
    copper.setStroke()
    for x in [CGFloat(452), CGFloat(572)] {
        let ring = NSBezierPath(ovalIn: NSRect(x: (x - 70) * s, y: 170 * s, width: 140 * s, height: 140 * s))
        ring.lineWidth = 30 * s
        ring.stroke()
    }
    image.unlockFocus()
    let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try draw(size: CGFloat(px)).write(to: out.appendingPathComponent("icon_\(name).png"))
}
print("wrote \(out.path)")
