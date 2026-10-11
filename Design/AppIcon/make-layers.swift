// Renders the layers of Winnow's app icon (concept D, the filmstrip) as 1024×1024 transparent PNGs
// for Winnow/AppIcon.icon. The background is the icon's fill in icon.json; masking, shadows,
// specular highlights and the dark / tinted variants come from the system.
//
//   swiftc -O -o /tmp/make-layers Design/AppIcon/make-layers.swift && /tmp/make-layers Winnow/AppIcon.icon/Assets
import AppKit

let S: CGFloat = 1024
let amber = CGColor(srgbRed: 0xF5 / 255, green: 0xC1 / 255, blue: 0x5A / 255, alpha: 1)

func rgb(_ h: UInt32, _ a: CGFloat = 1) -> CGColor {
    let r: CGFloat = CGFloat((h >> 16) & 0xFF) / 255
    let g: CGFloat = CGFloat((h >> 8) & 0xFF) / 255
    let b: CGFloat = CGFloat(h & 0xFF) / 255
    return CGColor(srgbRed: r, green: g, blue: b, alpha: a)
}

func gradient(_ stops: [(CGColor, CGFloat)]) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: stops.map(\.0) as CFArray, locations: stops.map(\.1))!
}

/// Shared geometry: the strip runs diagonally across the canvas.
enum Strip {
    static let angle: CGFloat = 0.32
    static let height = S * 0.40
    static let width = S * 1.6
    static let frameHeight = height * 0.60
    static let frameWidth = frameHeight * 1.5
    static let frameGap = S * 0.035

    static func frameRect(_ i: Int) -> CGRect {
        CGRect(x: CGFloat(i) * (frameWidth + frameGap) - frameWidth / 2, y: -frameHeight / 2, width: frameWidth, height: frameHeight)
    }

    static func apply(_ c: CGContext) {
        c.translateBy(x: S / 2, y: S / 2)
        c.rotate(by: angle)
    }
}

func render(_ name: String, to dir: String, _ draw: (CGContext) -> Void) {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4,
                               hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let ns = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ns
    draw(ns.cgContext)
    ns.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/\(name).png"))
}

/// Film base with sprocket holes, the unpicked frames and the edge print.
func filmLayer(_ c: CGContext) {
    Strip.apply(c)
    let h = Strip.height, w = Strip.width
    let strip = CGRect(x: -w / 2, y: -h / 2, width: w, height: h)

    let base = CGMutablePath()
    base.addRect(strip)
    let hole = CGSize(width: S * 0.032, height: S * 0.045)
    let pitch = S * 0.068
    var x = -w / 2 + pitch / 2
    while x < w / 2 {
        for y in [h / 2 - S * 0.035, -h / 2 + S * 0.035] {
            base.addPath(CGPath(roundedRect: CGRect(x: x - hole.width / 2, y: y - hole.height / 2, width: hole.width, height: hole.height),
                                cornerWidth: S * 0.008, cornerHeight: S * 0.008, transform: nil))
        }
        x += pitch
    }
    c.saveGState()
    c.addPath(base)
    c.clip(using: .evenOdd)
    c.drawLinearGradient(gradient([(rgb(0x3A322C), 0), (rgb(0x1E1A17), 0.5), (rgb(0x2C2622), 1)]),
                         start: CGPoint(x: 0, y: h / 2), end: CGPoint(x: 0, y: -h / 2), options: [])
    c.restoreGState()

    for i in [-2, -1, 1, 2] {
        let fr = Strip.frameRect(i)
        c.saveGState()
        c.addPath(CGPath(roundedRect: fr, cornerWidth: S * 0.012, cornerHeight: S * 0.012, transform: nil))
        c.clip()
        c.drawLinearGradient(gradient([(rgb(0x4A4E55), 0), (rgb(0x2E2B29), 0.55), (rgb(0x3D342C), 1)]),
                             start: CGPoint(x: fr.midX, y: fr.maxY), end: CGPoint(x: fr.midX, y: fr.minY), options: [])
        c.setFillColor(gray: 1, alpha: 0.06)
        c.fillEllipse(in: CGRect(x: fr.minX + fr.width * (i < 0 ? 0.55 : 0.15), y: fr.minY + fr.height * 0.15,
                                 width: fr.width * 0.35, height: fr.height * 0.55))
        c.restoreGState()
    }

    let font = NSFont.monospacedSystemFont(ofSize: S * 0.026, weight: .bold)
    let color = NSColor(srgbRed: 0.96, green: 0.70, blue: 0.30, alpha: 0.75)
    for (i, text) in ["10", "11", "WINNOW", "12", "▸12A", "13", "14"].enumerated() {
        (text as NSString).draw(at: CGPoint(x: -w * 0.42 + CGFloat(i) * S * 0.2, y: h / 2 - S * 0.083),
                                withAttributes: [.font: font, .foregroundColor: color])
    }
}

/// The picked frame, lit amber with a soft glow.
func pickLayer(_ c: CGContext) {
    Strip.apply(c)
    let fr = Strip.frameRect(0)
    let path = CGPath(roundedRect: fr, cornerWidth: S * 0.012, cornerHeight: S * 0.012, transform: nil)
    c.saveGState()
    c.setShadow(offset: .zero, blur: S * 0.09, color: amber.copy(alpha: 0.85))
    c.addPath(path)
    c.setFillColor(amber)
    c.fillPath()
    c.restoreGState()
    c.addPath(path)
    c.clip()
    c.drawRadialGradient(gradient([(rgb(0xFFE7AE), 0), (rgb(0xF5C15A), 0.6), (rgb(0xE3A23C), 1)]),
                         startCenter: CGPoint(x: fr.midX - fr.width * 0.15, y: fr.midY + fr.height * 0.2), startRadius: 0,
                         endCenter: CGPoint(x: fr.midX, y: fr.midY), endRadius: fr.width * 0.75, options: [.drawsAfterEndLocation])
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
render("film", to: dir, filmLayer)
render("pick", to: dir, pickLayer)
