import Foundation
import ImageIO

struct Exif: Hashable, Sendable {
    var make: String?
    var model: String?
    var lens: String?
    var exposureTime: Double?
    var fNumber: Double?
    var iso: Int?
    var focalLength: Double?
    var dateTaken: Date?
    var filmSimulation: String?

    var camera: String? {
        guard let model else { return make }
        guard let make, !model.uppercased().hasPrefix(make.uppercased()) else { return model }
        return "\(make) \(model)"
    }

    var shutterText: String? {
        guard let t = exposureTime, t > 0 else { return nil }
        if t >= 1 { return t == t.rounded() ? "\(Int(t))s" : String(format: "%.1fs", t) }
        return "1/\(Int((1 / t).rounded()))"
    }

    var apertureText: String? {
        guard let f = fNumber else { return nil }
        return f == f.rounded() ? "f/\(Int(f))" : String(format: "f/%.1f", f)
    }

    var isoText: String? { iso.map { "ISO \($0)" } }

    var focalText: String? {
        guard let f = focalLength else { return nil }
        return f == f.rounded() ? "\(Int(f)) mm" : String(format: "%.1f mm", f)
    }

    /// "1/250 · f/2.8 · ISO 160"
    var exposureLine: String {
        [shutterText, apertureText, isoText].compactMap { $0 }.joined(separator: " · ")
    }
}

enum ExifReader {
    /// Reads EXIF from the cheapest source: the JPG sibling, else the RAF's embedded JPEG, else the RAF.
    static func read(_ photo: Photo) -> Exif {
        var exif = Exif()
        var header: Data?
        if let jpg = photo.jpg {
            if let src = CGImageSourceCreateWithURL(jpg as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
                exif = parse(src)
            }
            header = RAFFile.readBytes(jpg, offset: 0, length: 256 * 1024)
        } else if let raf = photo.raf {
            if let range = RAFFile.embeddedJPEGRange(raf) {
                header = RAFFile.readBytes(raf, offset: range.offset, length: min(range.length, 256 * 1024))
            }
            if let header, let src = CGImageSourceCreateWithData(header as CFData, nil) {
                exif = parse(src)
            }
            if exif.model == nil,
               let src = CGImageSourceCreateWithURL(raf as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary) {
                exif = parse(src)
            }
        }
        if let header { exif.filmSimulation = FujiMakerNote.filmSimulation(jpegHeader: header) }
        return exif
    }

    static func parse(_ source: CGImageSource) -> Exif {
        guard let props = CGImageSourceCopyPropertiesAtIndex(source, 0, [kCGImageSourceShouldCache: false] as CFDictionary)
                as? [CFString: Any] else { return Exif() }
        let tiff = props[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exifDict = props[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let aux = props[kCGImagePropertyExifAuxDictionary] as? [CFString: Any] ?? [:]
        var e = Exif()
        e.make = (tiff[kCGImagePropertyTIFFMake] as? String)?.trimmingCharacters(in: .whitespaces)
        e.model = (tiff[kCGImagePropertyTIFFModel] as? String)?.trimmingCharacters(in: .whitespaces)
        e.lens = (exifDict[kCGImagePropertyExifLensModel] as? String) ?? (aux[kCGImagePropertyExifAuxLensModel] as? String)
        e.exposureTime = exifDict[kCGImagePropertyExifExposureTime] as? Double
        e.fNumber = exifDict[kCGImagePropertyExifFNumber] as? Double
        e.iso = (exifDict[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        e.focalLength = exifDict[kCGImagePropertyExifFocalLength] as? Double
        if let s = exifDict[kCGImagePropertyExifDateTimeOriginal] as? String {
            e.dateTaken = parseDate(s, offset: exifDict[kCGImagePropertyExifOffsetTimeOriginal] as? String)
        }
        return e
    }

    static func parseDate(_ s: String, offset: String?) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy:MM:dd HH:mm:ss"
        f.timeZone = .current
        return f.date(from: s)
    }
}

/// Reads byte ranges from files and finds the JPEG preview embedded in a RAF.
enum RAFFile {
    /// RAF header: "FUJIFILMCCD-RAW", JPEG offset at byte 84 and length at 88, big-endian.
    static func embeddedJPEGRange(_ url: URL) -> (offset: Int, length: Int)? {
        guard let header = readBytes(url, offset: 0, length: 92), header.count >= 92,
              header.starts(with: Data("FUJIFILMCCD-RAW".utf8)) else { return nil }
        let offset = Int(header.uint32BE(at: 84))
        let length = Int(header.uint32BE(at: 88))
        guard offset > 0, length > 0 else { return nil }
        return (offset, length)
    }

    static func embeddedJPEG(_ url: URL) -> Data? {
        guard let r = embeddedJPEGRange(url) else { return nil }
        return readBytes(url, offset: r.offset, length: r.length)
    }

    static func readBytes(_ url: URL, offset: Int, length: Int) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: UInt64(offset))
            return try handle.read(upToCount: length)
        } catch { return nil }
    }
}

/// Decodes the film simulation from Fujifilm's MakerNote.
enum FujiMakerNote {
    static func filmSimulation(jpegHeader data: Data) -> String? {
        guard let note = makerNote(inJPEG: data) else { return nil }
        return filmSimulation(makerNote: note)
    }

    /// Finds the MakerNote (EXIF tag 0x927C) inside a JPEG's APP1 segment.
    static func makerNote(inJPEG data: Data) -> Data? {
        let bytes = [UInt8](data)
        guard bytes.count > 4, bytes[0] == 0xFF, bytes[1] == 0xD8 else { return nil }
        var i = 2
        while i + 4 <= bytes.count {
            guard bytes[i] == 0xFF else { return nil }
            let marker = bytes[i + 1]
            let len = Int(bytes[i + 2]) << 8 | Int(bytes[i + 3])
            if marker == 0xE1, i + 10 <= bytes.count,
               Array(bytes[(i + 4)..<(i + 10)]) == [0x45, 0x78, 0x69, 0x66, 0, 0] {
                let tiffStart = i + 10
                let end = min(bytes.count, i + 2 + len)
                return makerNote(inTIFF: Array(bytes[tiffStart..<end]))
            }
            if marker == 0xDA { return nil }
            i += 2 + len
        }
        return nil
    }

    static func makerNote(inTIFF t: [UInt8]) -> Data? {
        guard t.count >= 8 else { return nil }
        let little = t[0] == 0x49
        let reader = ByteReader(bytes: t, littleEndian: little)
        guard let ifd0 = reader.u32(4),
              let exifOffset = reader.ifdEntry(at: Int(ifd0), tag: 0x8769)?.value,
              let note = reader.ifdEntry(at: Int(exifOffset), tag: 0x927C) else { return nil }
        let start = Int(note.value), count = Int(note.count)
        guard start >= 0, start + count <= t.count else { return nil }
        return Data(t[start..<(start + count)])
    }

    static func filmSimulation(makerNote: Data) -> String? {
        let b = [UInt8](makerNote)
        guard b.count > 12, b.starts(with: Array("FUJIFILM".utf8)) else { return nil }
        let reader = ByteReader(bytes: b, littleEndian: true)  // Fuji MakerNotes are always little-endian
        guard let ifd = reader.u32(8) else { return nil }
        let saturation = reader.ifdEntry(at: Int(ifd), tag: 0x1003).map { $0.value & 0xFFFF }
        let filmMode = reader.ifdEntry(at: Int(ifd), tag: 0x1401).map { $0.value & 0xFFFF }
        if let s = saturation, let mono = monochrome[s] { return mono }
        if let f = filmMode { return filmModes[f] ?? "Unknown" }
        return nil
    }

    static let filmModes: [UInt32: String] = [
        0x000: "Provia/Standard",
        0x100: "Studio Portrait",
        0x110: "Studio Portrait Enhanced Saturation",
        0x120: "Astia/Soft",
        0x130: "Studio Portrait Increased Sharpness",
        0x200: "Velvia/Vivid",
        0x300: "Studio Portrait Ex",
        0x400: "Velvia",
        0x500: "Pro Neg. Std",
        0x501: "Pro Neg. Hi",
        0x600: "Classic Chrome",
        0x700: "Eterna",
        0x800: "Classic Negative",
        0x900: "Eterna Bleach Bypass",
        0xA00: "Nostalgic Neg.",
        0xB00: "Reala Ace",
    ]

    static let monochrome: [UInt32: String] = [
        0x300: "Monochrome",
        0x301: "Monochrome + R",
        0x302: "Monochrome + Ye",
        0x303: "Monochrome + G",
        0x310: "Sepia",
        0x500: "Acros",
        0x501: "Acros + R",
        0x502: "Acros + Ye",
        0x503: "Acros + G",
    ]
}

/// Minimal TIFF/IFD reader.
struct ByteReader {
    let bytes: [UInt8]
    let littleEndian: Bool

    func u16(_ at: Int) -> UInt32? {
        guard at >= 0, at + 2 <= bytes.count else { return nil }
        let a = UInt32(bytes[at]), b = UInt32(bytes[at + 1])
        return littleEndian ? a | b << 8 : a << 8 | b
    }

    func u32(_ at: Int) -> UInt32? {
        guard at >= 0, at + 4 <= bytes.count else { return nil }
        let v = (0..<4).map { UInt32(bytes[at + $0]) }
        return littleEndian ? v[0] | v[1] << 8 | v[2] << 16 | v[3] << 24 : v[0] << 24 | v[1] << 16 | v[2] << 8 | v[3]
    }

    /// Returns (type, count, value) where value is the inline value (SHORT/LONG) or offset.
    func ifdEntry(at ifd: Int, tag: UInt32) -> (type: UInt32, count: UInt32, value: UInt32)? {
        guard let n = u16(ifd), n < 1000 else { return nil }
        for i in 0..<Int(n) {
            let e = ifd + 2 + i * 12
            guard let t = u16(e), let type = u16(e + 2), let count = u32(e + 4) else { return nil }
            guard t == tag else { continue }
            let value: UInt32? = (type == 3 && count <= 2) ? u16(e + 8) : u32(e + 8)
            return value.map { (type, count, $0) }
        }
        return nil
    }
}

extension Data {
    func uint32BE(at offset: Int) -> UInt32 {
        let s = startIndex + offset
        return UInt32(self[s]) << 24 | UInt32(self[s + 1]) << 16 | UInt32(self[s + 2]) << 8 | UInt32(self[s + 3])
    }
}
