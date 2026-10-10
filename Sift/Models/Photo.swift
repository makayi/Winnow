import Foundation

/// One photo on the card. A RAF and a JPG (or HEIF) sharing a basename are one photo.
struct Photo: Identifiable, Hashable, Sendable {
    /// Stable key, lowercased: "100_fuji/dscf4503". Used for flags and import records.
    let id: String
    let basename: String
    /// Folder relative to DCIM (or to the opened folder), e.g. "100_FUJI".
    let folder: String
    var raf: URL?
    /// The processed sibling: JPG, or HEIF on cameras set to HEIF.
    var jpg: URL?
    var rafSize: Int64 = 0
    var jpgSize: Int64 = 0
    /// File creation date; used for sorting and until EXIF loads.
    var fileDate: Date

    static func makeID(folder: String, basename: String) -> String {
        "\(folder)/\(basename)".lowercased()
    }

    var byteSize: Int64 { rafSize + jpgSize }
    var files: [URL] { [raf, jpg].compactMap { $0 } }
    var isEmpty: Bool { raf == nil && jpg == nil }

    /// Cheapest file to preview: the JPG sibling when present.
    var previewURL: URL? { jpg ?? raf }

    var jpgExtension: String { jpg?.pathExtension.uppercased() ?? "JPG" }

    var kindLabel: String {
        switch (raf != nil, jpg != nil) {
        case (true, true): "RAF+\(jpgExtension)"
        case (true, false): "RAF"
        case (false, true): jpgExtension
        case (false, false): ""
        }
    }

    /// "RAF + JPG" with spaces, for the loupe title.
    var kindLabelSpaced: String { kindLabel.replacingOccurrences(of: "+", with: " + ") }
}
