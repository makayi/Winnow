// Renders the still assets for the portrait product demo (1080×1920): background, title and end cards,
// captions, key badges, the window mask and its shadow. Usage: make-assets <out dir> <Winnow.app>
import AppKit

let W: CGFloat = 1080, H: CGFloat = 1920
let out = CommandLine.arguments[1], appPath = CommandLine.arguments[2]
let ink = NSColor(srgbRed: 0x1B / 255, green: 0x1B / 255, blue: 0x1D / 255, alpha: 1)
let amber = NSColor(srgbRed: 0xF5 / 255, green: 0xC1 / 255, blue: 0x5A / 255, alpha: 1)

/// Window geometry on the canvas (top-left origin), shared with build-video.py.
let win = CGRect(x: 40, y: 560, width: 1000, height: 958)
let winRadius: CGFloat = 26

func canvas(_ name: String, size: CGSize = CGSize(width: W, height: H), _ draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size.width), pixelsHigh: Int(size.height), bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    let c = ns.cgContext
    c.translateBy(x: 0, y: size.height)  // top-left origin like the video
    c.scaleBy(x: 1, y: -1)
    draw(c)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(name).png"))
}

func text(_ s: String, font: NSFont, color: NSColor, centerX: CGFloat, top: CGFloat, width: CGFloat = W - 120, lineSpacing: CGFloat = 4) -> CGFloat {
    let style = NSMutableParagraphStyle()
    style.alignment = .center
    style.lineSpacing = lineSpacing
    let str = NSAttributedString(string: s, attributes: [.font: font, .foregroundColor: color, .paragraphStyle: style])
    let bounds = str.boundingRect(with: CGSize(width: width, height: 2000), options: [.usesLineFragmentOrigin, .usesFontLeading])
    // Flip back for AppKit text drawing within our flipped context.
    NSGraphicsContext.saveGraphicsState()
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.saveGState()
    ctx.translateBy(x: 0, y: top + bounds.height)
    ctx.scaleBy(x: 1, y: -1)
    str.draw(with: CGRect(x: centerX - width / 2, y: 0, width: width, height: bounds.height), options: [.usesLineFragmentOrigin, .usesFontLeading])
    ctx.restoreGState()
    NSGraphicsContext.restoreGraphicsState()
    return bounds.height
}

func rounded(_ size: CGFloat, _ weight: NSFont.Weight) -> NSFont {
    let base = NSFont.systemFont(ofSize: size, weight: weight)
    return NSFont(descriptor: base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor, size: size) ?? base
}

let icon = NSWorkspace.shared.icon(forFile: appPath)
func drawIcon(_ c: CGContext, _ rect: CGRect) {
    c.saveGState()
    c.translateBy(x: 0, y: rect.minY + rect.maxY)
    c.scaleBy(x: 1, y: -1)
    icon.draw(in: rect)
    c.restoreGState()
}

func background(_ c: CGContext) {
    let g = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                       colors: [NSColor.white.cgColor, NSColor(srgbRed: 0.945, green: 0.949, blue: 0.957, alpha: 1).cgColor] as CFArray, locations: [0.35, 1])!
    c.drawLinearGradient(g, start: .zero, end: CGPoint(x: 0, y: H), options: [])
}

canvas("bg") { background($0) }

canvas("shadow") { c in
    c.setShadow(offset: CGSize(width: 0, height: 30), blur: 70, color: NSColor(white: 0, alpha: 0.22).cgColor)
    c.setFillColor(NSColor(white: 0.5, alpha: 1).cgColor)
    c.addPath(CGPath(roundedRect: win.insetBy(dx: 6, dy: 6), cornerWidth: winRadius, cornerHeight: winRadius, transform: nil))
    c.fillPath()
    // Leave only the shadow: punch out the window area.
    c.setShadow(offset: .zero, blur: 0, color: nil)
    c.setBlendMode(.clear)
    c.addPath(CGPath(roundedRect: win, cornerWidth: winRadius, cornerHeight: winRadius, transform: nil))
    c.fillPath()
}

canvas("mask", size: win.size) { c in
    c.setFillColor(NSColor.black.cgColor)
    c.fill(CGRect(origin: .zero, size: win.size))
    c.setFillColor(NSColor.white.cgColor)
    c.addPath(CGPath(roundedRect: CGRect(origin: .zero, size: win.size), cornerWidth: winRadius, cornerHeight: winRadius, transform: nil))
    c.fillPath()
}

canvas("brand") { c in
    let iconSize: CGFloat = 64
    let label = NSAttributedString(string: "Winnow", attributes: [.font: NSFont.systemFont(ofSize: 34, weight: .semibold), .foregroundColor: ink])
    let total = iconSize + 16 + label.size().width
    let x = (W - total) / 2, y: CGFloat = 1700
    drawIcon(c, CGRect(x: x, y: y, width: iconSize, height: iconSize))
    _ = text("Winnow", font: .systemFont(ofSize: 34, weight: .semibold), color: ink, centerX: x + iconSize + 16 + label.size().width / 2, top: y + 10, width: label.size().width + 10)
}

/// Big statement card, text only, centred.
func statement(_ name: String, _ headline: String, _ sub: String? = nil) {
    canvas(name) { c in
        background(c)
        let h = text(headline, font: .systemFont(ofSize: 74, weight: .bold), color: ink, centerX: W / 2, top: 780, width: W - 160, lineSpacing: 6)
        if let sub { _ = text(sub, font: .systemFont(ofSize: 40, weight: .regular), color: ink.withAlphaComponent(0.55), centerX: W / 2, top: 780 + h + 36, width: W - 160) }
    }
}

/// Card with the app icon and name.
func brandCard(_ name: String, headline: String, sub: String?, footer: String?) {
    canvas(name) { c in
        background(c)
        let iconSize: CGFloat = 360
        drawIcon(c, CGRect(x: (W - iconSize) / 2, y: 520, width: iconSize, height: iconSize))
        _ = text("Winnow", font: .systemFont(ofSize: 96, weight: .bold), color: ink, centerX: W / 2, top: 930)
        _ = text(headline, font: .systemFont(ofSize: 46, weight: .medium), color: ink.withAlphaComponent(0.72), centerX: W / 2, top: 1070, lineSpacing: 8)
        if let sub { _ = text(sub, font: .systemFont(ofSize: 34, weight: .regular), color: ink.withAlphaComponent(0.5), centerX: W / 2, top: 1240) }
        if let footer { _ = text(footer, font: .systemFont(ofSize: 30, weight: .medium), color: ink.withAlphaComponent(0.45), centerX: W / 2, top: 1640) }
    }
}

// The problem, in plain words. Claims checked: Lightroom Classic has no option to delete photos from a
// card after import (long-standing Adobe feature request); Apple Photos imports only into its own library.
statement("intro-1", "400 photos\non your card.", "You want maybe 20.")
statement("intro-2", "Lightroom Classic can't\ndelete them from your card\nafter import.")
statement("intro-3", "Apple Photos puts\neverything into its\nown library.")
brandCard("title", headline: "Pick your best,\nright off the card.", sub: nil, footer: nil)
brandCard("end", headline: "See every shot big.\nPick your favourites.\nCopy only those.", sub: nil, footer: "Made for Mac")

let captions: [(String, String, String)] = [
    ("grow", "See every shot big", "Right off the SD card. Nothing to import first."),
    ("cull", "Pick your favourites\nwith one key", "Press P to keep a photo, X to skip it"),
    ("loupe", "Look closer before\nyou decide", "With the camera settings for every shot"),
    ("import", "Copy only the ones\nyou picked", "Into your own folders. Every copy double-checked."),
    ("delete", "Then free up your card", "Winnow only deletes photos it copied safely"),
]
for (id, headline, sub) in captions {
    canvas("cap-\(id)") { c in
        let h = text(headline, font: .systemFont(ofSize: 66, weight: .bold), color: ink, centerX: W / 2, top: 200, lineSpacing: 2)
        _ = text(sub, font: .systemFont(ofSize: 36, weight: .regular), color: ink.withAlphaComponent(0.6), centerX: W / 2, top: 200 + h + 22)
    }
}

let keys: [(String, String)] = [("P", "P"), ("X", "X"), ("right", "→"), ("space", "Space"), ("cmd-plus", "⌘ +"), ("cmd-i", "⌘ I"), ("return", "↩")]
for (id, label) in keys {
    canvas("key-\(id)") { c in
        let font = rounded(54, .semibold)
        let str = NSAttributedString(string: label, attributes: [.font: font])
        let w = max(120, str.size().width + 64), h: CGFloat = 116
        let r = CGRect(x: (W - w) / 2, y: 1560, width: w, height: h)
        c.setShadow(offset: CGSize(width: 0, height: 8), blur: 22, color: NSColor(white: 0, alpha: 0.18).cgColor)
        c.setFillColor(NSColor.white.cgColor)
        c.addPath(CGPath(roundedRect: r, cornerWidth: 26, cornerHeight: 26, transform: nil))
        c.fillPath()
        c.setShadow(offset: .zero, blur: 0, color: nil)
        // Key cap bottom edge.
        c.setStrokeColor(NSColor(white: 0, alpha: 0.12).cgColor)
        c.setLineWidth(3)
        c.addPath(CGPath(roundedRect: r.insetBy(dx: 1.5, dy: 1.5), cornerWidth: 25, cornerHeight: 25, transform: nil))
        c.strokePath()
        let color = label == "P" ? NSColor(srgbRed: 0.70, green: 0.48, blue: 0.07, alpha: 1) : (label == "X" ? NSColor(srgbRed: 0.77, green: 0.26, blue: 0.17, alpha: 1) : ink)
        _ = text(label, font: font, color: color, centerX: W / 2, top: r.minY + (h - str.size().height) / 2, width: w)
    }
}
print("assets ok")
