// Renders the portrait demo with motion: a virtual camera that zooms and pans over the screen
// recording (camera.json), a spring entrance for the window, sliding captions, popping key badges,
// animated intro/end cards and a slowly drifting background. Video only; mux audio separately.
//
// usage: render-demo <demo dir> <assets dir> <camera.json> <out.mov> <t0> <card starts, e.g. 0,2.364>
import AVFoundation
import AppKit
import CoreImage

let args = CommandLine.arguments
let demoDir = args[1], assets = args[2], cameraPath = args[3], outPath = args[4]
let T0 = Double(args[5])!
let cardStarts = args[6].split(separator: ",").map { Double($0)! }

let W = 1080, H = 1920, FPS = 30.0
let view = CGRect(x: 40, y: 560, width: 1000, height: 958)  // window viewport, top-left origin
let radius: CGFloat = 26

// MARK: Inputs

struct Event: Decodable { let t: Double; let kind: String; let value: String }
struct Timeline: Decodable { let duration: [Event]; let events: [Event] }
struct Move: Decodable { let t: Double; let dur: Double; let cx: Double; let cy: Double; let zoom: Double }
struct Camera: Decodable { let moves: [Move]; let punch_keys: [String]; let punch: Double }

let timeline = try! JSONDecoder().decode(Timeline.self, from: Data(contentsOf: URL(fileURLWithPath: "\(demoDir)/timeline.json")))
let camera = try! JSONDecoder().decode(Camera.self, from: Data(contentsOf: URL(fileURLWithPath: cameraPath)))
let recLen = timeline.duration[0].t
let endIn = T0 + recLen - 0.2
let total = endIn + 3.6
let scenes = timeline.events.filter { $0.kind == "scene" }
let keys = timeline.events.filter { $0.kind == "key" }

func png(_ name: String) -> CGImage {
    let url = URL(fileURLWithPath: "\(assets)/\(name).png")
    let src = CGImageSourceCreateWithURL(url as CFURL, nil)!
    return CGImageSourceCreateImageAtIndex(src, 0, nil)!
}
let keyFiles = ["P": "P", "X": "X", "→": "right", "Space": "space", "⌘ +": "cmd-plus", "⌘ I": "cmd-i", "↩": "return"]
let bg = png("bg"), brand = png("brand"), endCard = png("end")
let intro = [png("intro-1"), png("title")]
var captions: [String: CGImage] = [:]
for s in scenes { captions[s.value] = png("cap-\(s.value)") }
var keyImages: [String: CGImage] = [:]
for (k, f) in keyFiles { keyImages[k] = png("key-\(f)") }

// MARK: Easing

func clamp(_ x: Double) -> Double { min(1, max(0, x)) }
func easeOut(_ x: Double) -> Double { 1 - pow(1 - clamp(x), 3) }                   // entrances
func easeIn(_ x: Double) -> Double { pow(clamp(x), 3) }                            // exits
func easeInOut(_ x: Double) -> Double {                                            // camera: smooth both ends
    let t = clamp(x); return t < 0.5 ? 4 * t * t * t : 1 - pow(-2 * t + 2, 3) / 2
}
func easeOutBack(_ x: Double, _ s: Double = 1.6) -> Double {                       // badges: small overshoot
    let t = clamp(x) - 1; return 1 + (s + 1) * t * t * t + s * t * t
}
/// Visible amount for an element shown from a to b with entry/exit durations.
func presence(_ t: Double, _ a: Double, _ b: Double, _ inDur: Double, _ outDur: Double) -> (enter: Double, exit: Double) {
    (enter: (t - a) / inDur, exit: (t - (b - outDur)) / outDur)
}

// MARK: Camera

func cameraAt(_ r: Double) -> (cx: Double, cy: Double, zoom: Double) {
    var cur = (cx: 0.5, cy: 0.5, zoom: 1.0)
    for m in camera.moves {
        if r <= m.t { break }
        let p = easeInOut((r - m.t) / m.dur)
        cur = (cur.cx + (m.cx - cur.cx) * p, cur.cy + (m.cy - cur.cy) * p, cur.zoom + (m.zoom - cur.zoom) * p)
    }
    // A small punch-in on each pick / reject, settling back.
    var punch = 0.0
    for k in keys where camera.punch_keys.contains(k.value) {
        let d = r - k.t
        if d >= 0 && d < 0.45 { punch += camera.punch * sin(min(1, d / 0.12) * .pi / 2) * exp(-d * 7) }
    }
    return (cur.cx, cur.cy, cur.zoom * (1 + punch))
}

// MARK: Recording frames

let ci = CIContext(options: [.useSoftwareRenderer: false])
let asset = AVURLAsset(url: URL(fileURLWithPath: "\(demoDir)/recording.mov"))
let reader = try! AVAssetReader(asset: asset)
let track = asset.tracks(withMediaType: .video)[0]
let readerOut = AVAssetReaderTrackOutput(track: track, outputSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
reader.add(readerOut)
reader.startReading()
var currentFrame: CGImage?
var pending: CMSampleBuffer? = readerOut.copyNextSampleBuffer()
func frame(at r: Double) -> CGImage? {
    while let s = pending, CMSampleBufferGetPresentationTimeStamp(s).seconds <= r {
        if let pb = CMSampleBufferGetImageBuffer(s) {
            let img = CIImage(cvPixelBuffer: pb)
            currentFrame = ci.createCGImage(img, from: img.extent)
        }
        pending = readerOut.copyNextSampleBuffer()
    }
    return currentFrame
}

// MARK: Drawing helpers (context is flipped to top-left origin)

func draw(_ c: CGContext, _ img: CGImage, in r: CGRect, alpha: Double = 1) {
    c.saveGState()
    c.setAlpha(CGFloat(alpha))
    c.translateBy(x: r.minX, y: r.maxY)
    c.scaleBy(x: 1, y: -1)
    c.draw(img, in: CGRect(x: 0, y: 0, width: r.width, height: r.height))
    c.restoreGState()
}

/// Draws a full-canvas overlay with a vertical offset and scale about an anchor.
func overlay(_ c: CGContext, _ img: CGImage, alpha: Double, dy: Double = 0, scale: Double = 1, anchor: CGPoint = CGPoint(x: 540, y: 960)) {
    guard alpha > 0.001 else { return }
    c.saveGState()
    c.translateBy(x: anchor.x, y: anchor.y + CGFloat(dy))
    c.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
    c.translateBy(x: -anchor.x, y: -anchor.y)
    draw(c, img, in: CGRect(x: 0, y: 0, width: W, height: H), alpha: alpha)
    c.restoreGState()
}

func render(_ c: CGContext, _ t: Double) {
    // Ambient: background plus a soft light that drifts slowly.
    draw(c, bg, in: CGRect(x: 0, y: 0, width: W, height: H))
    let gx = 540 + 220 * sin(t * 0.18), gy = 1000 + 160 * cos(t * 0.13)
    let glow = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                          colors: [CGColor(gray: 1, alpha: 0.9), CGColor(gray: 1, alpha: 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(glow, startCenter: CGPoint(x: gx, y: gy), startRadius: 0, endCenter: CGPoint(x: gx, y: gy), endRadius: 900, options: [])

    // Intro cards: rise in, rise out.
    for (i, img) in intro.enumerated() {
        let a = cardStarts[i], b = i + 1 < cardStarts.count ? cardStarts[i + 1] : T0
        let p = presence(t, a, b + 0.15, i == 0 ? 0.001 : 0.45, 0.3)
        let enter = i == 0 ? 1 : easeOut(p.enter), exit = easeIn(p.exit)
        guard t >= a, t < b + 0.15 else { continue }
        overlay(c, img, alpha: enter * (1 - exit), dy: 40 * (1 - enter) - 50 * exit, scale: 0.97 + 0.03 * enter)
    }

    // The window: springs in on the beat, camera moves inside it, eases away before the end card.
    if t >= T0 - 0.05, t < endIn + 0.5, let src = frame(at: max(0, t - T0)) {
        let enter = easeOut((t - T0) / 0.7)
        let exit = easeIn((t - endIn) / 0.45)
        let scale = (0.86 + 0.14 * easeOutBack((t - T0) / 0.8, 1.2)) * (1 - 0.08 * exit)
        let dy = 90 * (1 - enter) - 60 * exit
        let alpha = enter * (1 - exit)
        let vr = CGRect(x: view.midX - view.width * scale / 2, y: view.midY - view.height * scale / 2 + dy,
                        width: view.width * scale, height: view.height * scale)
        let path = CGPath(roundedRect: vr, cornerWidth: radius * scale, cornerHeight: radius * scale, transform: nil)
        // Secondary: the shadow grows with the window.
        c.saveGState()
        c.setAlpha(CGFloat(alpha))
        c.setShadow(offset: CGSize(width: 0, height: 28 * scale), blur: 70 * scale, color: CGColor(gray: 0, alpha: 0.24))
        c.setFillColor(CGColor(gray: 1, alpha: 1))
        c.addPath(path); c.fillPath()
        c.restoreGState()

        let cam = cameraAt(t - T0)
        let sw = Double(src.width), sh = Double(src.height)
        let cw = sw / cam.zoom, ch = sh / cam.zoom
        let x0 = min(max(cam.cx * sw - cw / 2, 0), sw - cw), y0 = min(max(cam.cy * sh - ch / 2, 0), sh - ch)
        if let crop = src.cropping(to: CGRect(x: x0, y: y0, width: cw, height: ch)) {
            c.saveGState()
            c.addPath(path); c.clip()
            c.interpolationQuality = .high
            draw(c, crop, in: vr, alpha: alpha)
            c.restoreGState()
        }
        overlay(c, brand, alpha: alpha, dy: 20 * (1 - enter))
    }

    // Captions: slide up and fade in, fade out quickly.
    for (i, s) in scenes.enumerated() {
        let a = T0 + s.t + (i == 0 ? 0.35 : 0.05)
        let b = T0 + (i + 1 < scenes.count ? scenes[i + 1].t : recLen - 0.2)
        guard t >= a, t < b, let img = captions[s.value] else { continue }
        let p = presence(t, a, b, 0.45, 0.25)
        let enter = easeOut(p.enter), exit = easeIn(p.exit)
        overlay(c, img, alpha: enter * (1 - exit), dy: 34 * (1 - enter) - 16 * exit)
    }

    // Key badges: pop in with a little overshoot.
    for (i, k) in keys.enumerated() {
        let a = T0 + k.t
        let next = i + 1 < keys.count ? T0 + keys[i + 1].t : a + 1
        let b = a + max(0.3, min(0.6, next - a - 0.03))
        guard t >= a, t < b, let img = keyImages[k.value] else { continue }
        let p = presence(t, a, b, 0.22, 0.12)
        let s = 0.6 + 0.4 * easeOutBack(p.enter)
        overlay(c, img, alpha: clamp(p.enter * 3) * (1 - easeIn(p.exit)), scale: s * (1 - 0.1 * easeIn(p.exit)), anchor: CGPoint(x: 540, y: 1618))
    }

    // End card: rises in as the window leaves.
    if t >= endIn {
        let e = easeOut((t - endIn - 0.1) / 0.6)
        overlay(c, endCard, alpha: e, dy: 50 * (1 - e), scale: 0.96 + 0.04 * e)
    }
}

// MARK: Encode

let outURL = URL(fileURLWithPath: outPath)
try? FileManager.default.removeItem(at: outURL)
let writer = try! AVAssetWriter(outputURL: outURL, fileType: .mov)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: W, AVVideoHeightKey: H,
    AVVideoCompressionPropertiesKey: [AVVideoAverageBitRateKey: 16_000_000, AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel],
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
    kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA, kCVPixelBufferWidthKey as String: W, kCVPixelBufferHeightKey as String: H,
])
writer.add(input)
writer.startWriting()
writer.startSession(atSourceTime: .zero)

let frames = Int(total * FPS)
for f in 0..<frames {
    while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.002) }
    var pb: CVPixelBuffer?
    CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &pb)
    guard let buf = pb else { fatalError("no pixel buffer") }
    CVPixelBufferLockBaseAddress(buf, [])
    let ctx = CGContext(data: CVPixelBufferGetBaseAddress(buf), width: W, height: H, bitsPerComponent: 8,
                        bytesPerRow: CVPixelBufferGetBytesPerRow(buf), space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue)!
    ctx.translateBy(x: 0, y: CGFloat(H))
    ctx.scaleBy(x: 1, y: -1)
    render(ctx, Double(f) / FPS)
    CVPixelBufferUnlockBaseAddress(buf, [])
    adaptor.append(buf, withPresentationTime: CMTime(value: CMTimeValue(f), timescale: CMTimeScale(FPS)))
    if f % 150 == 0 { print("frame \(f)/\(frames)") }
}
input.markAsFinished()
let done = DispatchSemaphore(value: 0)
writer.finishWriting { done.signal() }
done.wait()
print("wrote \(outPath) (\(String(format: "%.1f", total))s)")
