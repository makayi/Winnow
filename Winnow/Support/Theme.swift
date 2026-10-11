import AppKit
import SwiftUI

/// Semantic colours. Text, fills and separators come from the system so both appearances work;
/// only the pick / reject / success accents are Winnow's own, with a deeper ink for light mode.
enum Theme {
    /// Accent fills: rings, badges, filled buttons. Same in both appearances.
    static let pick = Color(hex: 0xF5C15A)
    static let reject = Color(hex: 0xF0735E)
    static let success = Color(hex: 0x78C88C)
    /// Text and glyphs drawn on an accent fill.
    static let onPick = Color(hex: 0x1B1B1D)

    /// Accent-coloured glyphs and text on ordinary surfaces, darker in light mode for contrast.
    static let pickInk = Color(light: 0xB27A12, dark: 0xF5C15A)
    static let rejectInk = Color(light: 0xC4432C, dark: 0xF0735E)
    static let successInk = Color(light: 0x2F8A49, dark: 0x78C88C)

    static let loupeBackground = Color(light: 0xF2F2F4, dark: 0x0B0B0D)
    static let placeholder = Color(nsColor: .quaternarySystemFill)
    static let tileFill = Color(nsColor: .quaternarySystemFill)
    static let separator = Color(nsColor: .separatorColor)

    enum Radius {
        static let small: CGFloat = 12
        static let thumb: CGFloat = 14
        static let panel: CGFloat = 24
    }

    static let minThumb: CGFloat = 140
    static let maxThumb: CGFloat = 420
    static let thumbStep: CGFloat = 40
    static let gridSpacingH: CGFloat = 16
    static let gridSpacingV: CGFloat = 20

    static let mono = Font.system(size: 12, design: .monospaced)
}

extension Color {
    init(hex: UInt32, opacity: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: opacity
        )
    }

    /// A colour that follows the window's appearance.
    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

extension View {
    /// Liquid Glass for Winnow's own floating controls (the system provides it for toolbars,
    /// sidebars, inspectors and sheets). Debug snapshots, which can't capture glass, get a flat fill.
    @ViewBuilder
    func winnowGlass<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        #if DEBUG
        if DebugFlags.flatGlass {
            background(Color(nsColor: .windowBackgroundColor).opacity(0.92), in: shape)
        } else {
            glassEffect(glass, in: shape)
        }
        #else
        glassEffect(glass, in: shape)
        #endif
    }
}

#if DEBUG
enum DebugFlags {
    static let flatGlass = UserDefaults.standard.string(forKey: "snapshots") != nil
}
#endif

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    static func roundBytes(_ n: Int64) -> String {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowsNonnumericFormatting = false
        return f.string(fromByteCount: n)
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy"
        return f
    }()

    static let takenFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        f.timeStyle = .short
        return f
    }()

    static func abbreviatedPath(_ path: String) -> String {
        (path as NSString).abbreviatingWithTildeInPath
    }

    static func plural(_ n: Int, _ singular: String, _ plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : (plural ?? singular + "s"))"
    }
}
