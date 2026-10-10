import SwiftUI

enum Theme {
    static let windowBackground = Color(hex: 0x0F0F11)
    static let loupeBackground = Color(hex: 0x0B0B0D)
    static let textPrimary = Color(hex: 0xF2F2F4)
    static let textSecondary = Color(hex: 0xF2F2F4, opacity: 0.66)
    static let textTertiary = Color(hex: 0xF2F2F4, opacity: 0.45)
    static let pick = Color(hex: 0xF5C15A)
    static let onPick = Color(hex: 0x1B1B1D)
    static let reject = Color(hex: 0xF0735E)
    static let success = Color(hex: 0x78C88C)
    static let hairline = Color.white.opacity(0.08)

    enum Radius {
        static let small: CGFloat = 12
        static let thumb: CGFloat = 14
        static let panel: CGFloat = 24
        static let sheet: CGFloat = 30
    }

    static let sidebarWidth: CGFloat = 236
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
}

enum Format {
    static func bytes(_ n: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: n, countStyle: .file)
    }

    /// "48 MB" style without decimals for inspector rows.
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

extension View {
    /// Floating Liquid Glass chrome. Debug snapshots (which can't capture glass) get a flat fill instead.
    @ViewBuilder
    func siftGlass<S: Shape>(_ glass: Glass = .regular, in shape: S) -> some View {
        #if DEBUG
        if DebugFlags.flatGlass {
            background(Color(hex: 0x26262B, opacity: 0.92), in: shape)
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
