#if DEBUG
import AppKit

/// Debug-only: `Sift -open <folder> -snapshots <dir>` walks through the main screens and
/// writes a PNG of the window after each step, for checking layout without a human at the screen.
@MainActor
enum DebugSnapshots {
    static func runIfRequested(app: AppModel) {
        guard let dir = UserDefaults.standard.string(forKey: "snapshots") else { return }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let steps: [(String, () -> Void)] = [
            ("1-grid", {}),
            ("2-flagged", {
                guard let s = app.session else { return }
                for (i, p) in s.visible.prefix(12).enumerated() where i % 3 == 0 { s.setFlag(.pick, for: p.id) }
                if s.visible.count > 4 { s.setFlag(.reject, for: s.visible[4].id) }
                s.selectedID = s.visible.dropFirst(3).first?.id
            }),
            ("3-big-thumbs", { app.thumbnailSize = 420 }),
            ("4-loupe", { app.thumbnailSize = 240; app.openLoupe() }),
            ("5-import", { app.closeLoupe(); app.openImport() }),
            ("6-small-thumbs", { app.closeImport(); app.thumbnailSize = 140 }),
        ]
        var importSteps: [(String, () -> Void)] = []
        if let dest = UserDefaults.standard.string(forKey: "importTo") {
            // Runs a real import into `dest`, then answers the delete prompt. Only use on a scratch card.
            importSteps = [
                ("7-copying", { app.thumbnailSize = 240; app.openImport(); app.importFlow?.options.destinationPath = dest; app.importFlow?.start() }),
                ("8-asking", { app.importFlow?.alsoDeleteRejects = true }),
                ("9-finished", { app.importFlow?.deleteFromCard() }),
                ("10-after", { app.importFlow?.close() }),
            ]
        }
        Task {
            try? await Task.sleep(for: .seconds(4))
            for (name, action) in steps + importSteps {
                action()
                try? await Task.sleep(for: .seconds(name == "7-copying" ? 0.6 : 2.5))
                snapshot(to: out.appendingPathComponent("\(name).png"))
            }
            NSApp.terminate(nil)
        }
    }

    static func snapshot(to url: URL) {
        guard let window = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil }),
              let view = window.contentView?.superview else { return }
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }
}
#endif
