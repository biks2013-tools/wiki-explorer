// Draws the Wiki Explorer app icon into an .iconset (and optionally a 1024 px preview PNG).
//
//   swift scripts/make-icon.swift build/AppIcon.iconset [preview.png]
//
// Design: on a dark ink tile with a warm copper glow, two paper pages carry a small graph of linked
// nodes (the interlinked wiki); a copper magnifying glass enlarges part of that graph (exploring it).
// Palette: ink #1B1D21, copper #C8623A / #E08A5E, amber #E3A64A, paper #F6F3EC.
// Everything is vector-drawn in a 1024-unit space, so each size is rendered crisp; at 64 px and below
// the text lines are dropped and strokes thickened so the shape still reads.
import AppKit

let args = CommandLine.arguments
let out = URL(fileURLWithPath: args.count > 1 ? args[1] : "AppIcon.iconset")
let previewPath = args.count > 2 ? args[2] : nil
try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)

func rgb(_ hex: UInt32, _ a: CGFloat = 1) -> CGColor {
    CGColor(red: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: a)
}

let ink = rgb(0x1B1D21), inkLight = rgb(0x2C3038), inkDeep = rgb(0x101215)
let copper = rgb(0xC8623A), copperLight = rgb(0xE08A5E), copperDark = rgb(0x8E3F22), amber = rgb(0xE3A64A)
let paper = rgb(0xF6F3EC), paperShade = rgb(0xE6E0D3)

func linear(_ ctx: CGContext, _ colors: [CGColor], from: CGPoint, to: CGPoint) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawLinearGradient(g, start: from, end: to, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
}

func radial(_ ctx: CGContext, _ colors: [CGColor], center: CGPoint, radius: CGFloat) {
    let g = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: nil)!
    ctx.drawRadialGradient(g, startCenter: center, startRadius: 0, endCenter: center, endRadius: radius, options: [])
}

/// The graph drawn on the front page (page-local coordinates, origin bottom-left of the page).
let nodes: [CGPoint] = [CGPoint(x: 78, y: 228), CGPoint(x: 176, y: 300), CGPoint(x: 300, y: 168), CGPoint(x: 132, y: 98), CGPoint(x: 262, y: 300), CGPoint(x: 360, y: 92)]
let edges: [(Int, Int)] = [(0, 1), (1, 2), (0, 3), (3, 2), (1, 4), (4, 2), (2, 5)]

func drawGraph(_ ctx: CGContext, scale: CGFloat, small: Bool) {
    ctx.setLineCap(.round)
    ctx.setStrokeColor(rgb(0xC8623A, 0.75))
    ctx.setLineWidth((small ? 14 : 9) * scale)
    for (a, b) in edges {
        ctx.move(to: nodes[a]); ctx.addLine(to: nodes[b]); ctx.strokePath()
    }
    for (i, p) in nodes.enumerated() {
        let r: CGFloat = (i == 2 ? 26 : 19) * (small ? 1.25 : 1) * scale
        ctx.setFillColor(i == 2 ? copper : (i == 4 ? amber : ink))
        ctx.fillEllipse(in: CGRect(x: p.x - r, y: p.y - r, width: 2 * r, height: 2 * r))
        ctx.setFillColor(rgb(0xFFFFFF, 0.35))
        let h = r * 0.42
        ctx.fillEllipse(in: CGRect(x: p.x - r * 0.45, y: p.y + r * 0.1, width: h, height: h))
    }
}

func draw(_ ctx: CGContext, px: CGFloat) {
    let small = px <= 64
    ctx.saveGState()
    ctx.scaleBy(x: px / 1024, y: px / 1024)

    // Tile: macOS icon grid (824 pt body, inset 100), soft drop shadow.
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    let tilePath = CGPath(roundedRect: tile, cornerWidth: 186, cornerHeight: 186, transform: nil)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 34, color: rgb(0x000000, 0.35))
    ctx.addPath(tilePath); ctx.setFillColor(ink); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.clip()
    linear(ctx, [inkLight, ink, inkDeep], from: CGPoint(x: 512, y: 924), to: CGPoint(x: 512, y: 100))
    radial(ctx, [rgb(0xC8623A, 0.45), rgb(0xC8623A, 0.0)], center: CGPoint(x: 600, y: 470), radius: 470)
    ctx.restoreGState()
    // Hairline highlight along the top edge.
    ctx.saveGState()
    ctx.addPath(tilePath); ctx.setStrokeColor(rgb(0xFFFFFF, 0.10)); ctx.setLineWidth(3); ctx.strokePath()
    ctx.restoreGState()

    // Back page, rotated left.
    let pageSize = CGSize(width: 430, height: 520)
    ctx.saveGState()
    ctx.translateBy(x: 300, y: 300); ctx.rotate(by: 0.16)
    ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 26, color: rgb(0x000000, 0.45))
    ctx.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: pageSize), cornerWidth: 26, cornerHeight: 26, transform: nil))
    ctx.setFillColor(paperShade); ctx.fillPath()
    ctx.restoreGState()

    // Front page, rotated slightly right, with a folded corner.
    ctx.saveGState()
    ctx.translateBy(x: 318, y: 262); ctx.rotate(by: -0.07)
    let page = CGMutablePath()
    page.move(to: CGPoint(x: 26, y: 0))
    page.addLine(to: CGPoint(x: pageSize.width - 26, y: 0))
    page.addQuadCurve(to: CGPoint(x: pageSize.width, y: 26), control: CGPoint(x: pageSize.width, y: 0))
    page.addLine(to: CGPoint(x: pageSize.width, y: pageSize.height - 86))
    page.addLine(to: CGPoint(x: pageSize.width - 86, y: pageSize.height))
    page.addLine(to: CGPoint(x: 26, y: pageSize.height))
    page.addQuadCurve(to: CGPoint(x: 0, y: pageSize.height - 26), control: CGPoint(x: 0, y: pageSize.height))
    page.addLine(to: CGPoint(x: 0, y: 26))
    page.addQuadCurve(to: CGPoint(x: 26, y: 0), control: .zero)
    page.closeSubpath()
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 30, color: rgb(0x000000, 0.5))
    ctx.addPath(page); ctx.setFillColor(paper); ctx.fillPath()
    ctx.restoreGState()
    // Fold.
    let fold = CGMutablePath()
    fold.move(to: CGPoint(x: pageSize.width, y: pageSize.height - 86))
    fold.addLine(to: CGPoint(x: pageSize.width - 86, y: pageSize.height - 86))
    fold.addLine(to: CGPoint(x: pageSize.width - 86, y: pageSize.height))
    fold.closeSubpath()
    ctx.addPath(fold); ctx.setFillColor(paperShade); ctx.fillPath()
    // Title and text lines.
    ctx.setLineCap(.round)
    ctx.setStrokeColor(ink); ctx.setLineWidth(small ? 30 : 22)
    ctx.move(to: CGPoint(x: 52, y: pageSize.height - 66)); ctx.addLine(to: CGPoint(x: small ? 300 : 250, y: pageSize.height - 66)); ctx.strokePath()
    if !small {
        ctx.setStrokeColor(rgb(0x1B1D21, 0.22)); ctx.setLineWidth(12)
        for (i, w) in [300.0, 250, 280].enumerated() {
            let y = pageSize.height - 120 - CGFloat(i) * 34
            ctx.move(to: CGPoint(x: 52, y: y)); ctx.addLine(to: CGPoint(x: 52 + w, y: y)); ctx.strokePath()
        }
    }
    // Graph, sitting in the lower half of the page.
    ctx.saveGState()
    ctx.translateBy(x: 10, y: 0)
    drawGraph(ctx, scale: 1, small: small)
    ctx.restoreGState()

    // Magnifying glass over the graph: lens centred on node 2 (lower right), showing it enlarged.
    let lensCenterPage = CGPoint(x: nodes[2].x + 10 + 20, y: nodes[2].y - 10)
    ctx.restoreGState()
    // Convert the lens centre from page space to tile space (same transform as the front page).
    let t = CGAffineTransform(translationX: 318, y: 262).rotated(by: -0.07)
    let lens = lensCenterPage.applying(t)
    let lensR: CGFloat = 128

    // Handle (behind the rim), towards bottom-right.
    ctx.saveGState()
    ctx.translateBy(x: lens.x, y: lens.y); ctx.rotate(by: -.pi / 4)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 18, color: rgb(0x000000, 0.45))
    let handle = CGPath(roundedRect: CGRect(x: lensR + 8, y: -34, width: 175, height: 68), cornerWidth: 34, cornerHeight: 34, transform: nil)
    ctx.addPath(handle); ctx.setFillColor(inkDeep); ctx.fillPath()
    ctx.restoreGState()
    ctx.saveGState()
    ctx.translateBy(x: lens.x, y: lens.y); ctx.rotate(by: -.pi / 4)
    ctx.addPath(handle); ctx.clip()
    linear(ctx, [rgb(0x3A3F48), inkDeep], from: CGPoint(x: 0, y: 34), to: CGPoint(x: 0, y: -34))
    // Copper ferrule where the handle meets the rim.
    ctx.addRect(CGRect(x: lensR + 8, y: -34, width: 44, height: 68)); ctx.clip()
    linear(ctx, [copperLight, copperDark], from: CGPoint(x: 0, y: 34), to: CGPoint(x: 0, y: -34))
    ctx.restoreGState()

    // Glass: the page content seen through the lens, enlarged 1.7x around node 2.
    let glass = CGRect(x: lens.x - lensR, y: lens.y - lensR, width: 2 * lensR, height: 2 * lensR)
    ctx.saveGState()
    ctx.addEllipse(in: glass); ctx.clip()
    ctx.setFillColor(paper); ctx.fill(glass)
    ctx.translateBy(x: lens.x, y: lens.y)
    ctx.scaleBy(x: 1.7, y: 1.7)
    ctx.rotate(by: -0.07)
    ctx.translateBy(x: -lensCenterPage.x, y: -lensCenterPage.y)
    ctx.translateBy(x: 10, y: 0)
    drawGraph(ctx, scale: 1, small: small)
    ctx.restoreGState()
    // Glass shading and highlight.
    ctx.saveGState()
    ctx.addEllipse(in: glass); ctx.clip()
    radial(ctx, [rgb(0xFFFFFF, 0.0), rgb(0x1B1D21, 0.10)], center: lens, radius: lensR)
    ctx.addEllipse(in: CGRect(x: lens.x - lensR * 0.62, y: lens.y + lensR * 0.18, width: lensR * 0.75, height: lensR * 0.42))
    ctx.setFillColor(rgb(0xFFFFFF, 0.22)); ctx.fillPath()
    ctx.restoreGState()
    // Rim: copper ring with a metallic gradient.
    ctx.saveGState()
    let rimWidth: CGFloat = small ? 46 : 38
    let ring = CGMutablePath()
    ring.addEllipse(in: glass.insetBy(dx: -rimWidth, dy: -rimWidth))
    ring.addEllipse(in: glass)
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 16, color: rgb(0x000000, 0.4))
    ctx.addPath(ring); ctx.setFillColor(copper); ctx.fillPath(using: .evenOdd)
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addPath(ring); ctx.clip(using: .evenOdd)
    linear(ctx, [rgb(0xF2B48E), copperLight, copper, copperDark], from: CGPoint(x: lens.x - lensR, y: lens.y + lensR), to: CGPoint(x: lens.x + lensR, y: lens.y - lensR))
    ctx.restoreGState()
    ctx.saveGState()
    ctx.addEllipse(in: glass.insetBy(dx: -rimWidth + 3, dy: -rimWidth + 3))
    ctx.setStrokeColor(rgb(0xFFFFFF, 0.25)); ctx.setLineWidth(3); ctx.strokePath()
    ctx.restoreGState()

    ctx.restoreGState()
}

func render(px: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let gc = NSGraphicsContext(bitmapImageRep: rep)!
    gc.imageInterpolation = .high
    let ctx = gc.cgContext
    ctx.setShouldAntialias(true)
    ctx.clear(CGRect(x: 0, y: 0, width: px, height: px))
    draw(ctx, px: CGFloat(px))
    gc.flushGraphics()
    return rep.representation(using: .png, properties: [:])!
}

for (name, px) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128), ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
    try render(px: px).write(to: out.appendingPathComponent("icon_\(name).png"))
}
if let previewPath { try render(px: 1024).write(to: URL(fileURLWithPath: previewPath)) }
print("wrote \(out.path)")
