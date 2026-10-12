// Renders the foreground layer of Winnow's app icon (K2: a white SD card with a photo on it) as a
// 1024×1024 transparent PNG for Winnow/AppIcon.icon. The contacts and the photo glyph are cut out,
// so the icon's black fill (set in icon.json) shows through. macOS adds the glass, shadows and the
// dark / tinted variants.
//
//   swiftc -O -o /tmp/make-layers Design/AppIcon/make-layers.swift && /tmp/make-layers Winnow/AppIcon.icon/Assets
import AppKit

let S: CGFloat = 1024

/// SD card outline: real 24 × 32 mm proportions with the notch at the top right.
func cardPath(x: CGFloat, y: CGFloat, w: CGFloat, h: CGFloat, r: CGFloat, cut: CGFloat) -> CGPath {
    let p = CGMutablePath()
    p.move(to: CGPoint(x: x + r, y: y))
    p.addLine(to: CGPoint(x: x + w - r, y: y)); p.addQuadCurve(to: CGPoint(x: x + w, y: y + r), control: CGPoint(x: x + w, y: y))
    p.addLine(to: CGPoint(x: x + w, y: y + h - cut))
    p.addLine(to: CGPoint(x: x + w - cut, y: y + h))
    p.addLine(to: CGPoint(x: x + r, y: y + h)); p.addQuadCurve(to: CGPoint(x: x, y: y + h - r), control: CGPoint(x: x, y: y + h))
    p.addLine(to: CGPoint(x: x, y: y + r)); p.addQuadCurve(to: CGPoint(x: x + r, y: y), control: CGPoint(x: x, y: y))
    p.closeSubpath()
    return p
}

func cardLayer(_ c: CGContext) {
    let w = S * 0.45, h = S * 0.60, x = (S - w) / 2, y = (S - h) / 2 - S * 0.01
    c.addPath(cardPath(x: x, y: y, w: w, h: h, r: S * 0.04, cut: S * 0.085))
    c.setFillColor(CGColor(gray: 1, alpha: 1)); c.fillPath()

    // Everything below is cut out of the card.
    c.setBlendMode(.clear)
    let cw = S * 0.045, gap = S * 0.026, top = y + h - S * 0.04
    for i in 0..<4 {
        let cx = x + S * 0.05 + CGFloat(i) * (cw + gap)
        c.addPath(CGPath(roundedRect: CGRect(x: cx, y: top - S * 0.10, width: cw, height: S * 0.10), cornerWidth: S * 0.012, cornerHeight: S * 0.012, transform: nil))
        c.fillPath()
    }
    let g = CGRect(x: x + w * 0.2, y: y + h * 0.14, width: w * 0.6, height: w * 0.42)
    c.fillEllipse(in: CGRect(x: g.minX + g.width * 0.60, y: g.minY + g.height * 0.56, width: g.width * 0.18, height: g.width * 0.18))
    let hills = CGMutablePath()
    hills.move(to: CGPoint(x: g.minX, y: g.minY))
    hills.addLine(to: CGPoint(x: g.minX + g.width * 0.34, y: g.minY + g.height * 0.46))
    hills.addLine(to: CGPoint(x: g.minX + g.width * 0.56, y: g.minY + g.height * 0.20))
    hills.addLine(to: CGPoint(x: g.minX + g.width * 0.72, y: g.minY + g.height * 0.34))
    hills.addLine(to: CGPoint(x: g.maxX, y: g.minY))
    hills.closeSubpath()
    c.addPath(hills); c.fillPath()
}

let dir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "."
try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S), bitsPerSample: 8, samplesPerPixel: 4,
                           hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
cardLayer(ctx.cgContext)
ctx.flushGraphics()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(dir)/card.png"))
