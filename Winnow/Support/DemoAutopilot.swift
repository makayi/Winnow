#if DEBUG
import AppKit
import ScreenCaptureKit
import SwiftUI

/// Debug-only product demo: `Winnow -open <scratch card> -folderIsCard YES -demo <out dir>`
/// plays a scripted walkthrough of the real app and records its window with ScreenCaptureKit.
/// Writes `<out>/recording.mov` and `<out>/timeline.json` (scene and key-press times) for editing.
/// Only ever point it at a scratch copy of a card: the walkthrough imports and deletes for real.
@MainActor
enum DemoAutopilot {
    struct Event: Codable { let t: Double; let kind: String; let value: String }

    static var isActive: Bool { UserDefaults.standard.string(forKey: "demo") != nil }
    /// Where the import really goes, while the sheet shows the user's normal destination.
    static var destinationOverride: String? { UserDefaults.standard.string(forKey: "demoImportTo") }
    static let importDelay: @Sendable (URL) throws -> Void = { _ in Thread.sleep(forTimeInterval: 0.14) }

    private static var events: [Event] = []
    private static var start = Date()
    private static var recorder: WindowRecorder?

    static func displayPath(_ path: String) -> String {
        guard isActive, let real = destinationOverride, path.hasPrefix(real) else { return path }
        return ImportOptions().destinationPath + path.dropFirst(real.count)
    }

    static func runIfRequested(app: AppModel) {
        guard let dir = UserDefaults.standard.string(forKey: "demo") else { return }
        let out = URL(fileURLWithPath: dir, isDirectory: true)
        try? FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let savedDefaults = ["importOptions", "thumbnailSize"].map { ($0, UserDefaults.standard.object(forKey: $0)) }
        NSApp.appearance = NSAppearance(named: UserDefaults.standard.string(forKey: "appearance") == "dark" ? .darkAqua : .aqua)

        // The demo shows default import options; the user's own settings come back before quitting.
        UserDefaults.standard.removeObject(forKey: "importOptions")
        func restoreDefaults() {
            for (key, value) in savedDefaults {
                if let value { UserDefaults.standard.set(value, forKey: key) } else { UserDefaults.standard.removeObject(forKey: key) }
            }
        }

        Task {
            guard let window = await placeWindow() else { restoreDefaults(); return fail("No window") }
            // Warm the preview cache at both sizes so the first frames aren't blank.
            app.thumbnailSize = 280
            try? await Task.sleep(for: .seconds(2.5))
            app.thumbnailSize = 150
            app.session?.selectedID = app.session?.visible.first?.id
            try? await Task.sleep(for: .seconds(2.5))

            do {
                let rec = WindowRecorder()
                try await rec.start(window: window, to: out.appendingPathComponent("recording.mov"))
                recorder = rec
            } catch {
                restoreDefaults()
                return fail("Recording failed: \(error.localizedDescription). Allow Winnow in System Settings › Privacy & Security › Screen & System Audio Recording, then run again.")
            }
            start = Date()
            await script(app: app, window: window)
            try? await recorder?.stop()
            let data = try? JSONEncoder().encode(["duration": [Event(t: elapsed, kind: "end", value: "")], "events": events])
            try? data?.write(to: out.appendingPathComponent("timeline.json"))
            print("DEMO DONE", elapsed)
            restoreDefaults()
            NSApp.terminate(nil)
        }
    }

    private static var elapsed: Double { Date().timeIntervalSince(start) }

    private static func fail(_ message: String) {
        print("DEMO FAILED: \(message)")
        NSApp.terminate(nil)
    }

    private static func scene(_ name: String) { events.append(Event(t: elapsed, kind: "scene", value: name)) }

    private static func wait(_ s: Double) async { try? await Task.sleep(for: .seconds(s)) }

    /// Sends a real key event through Winnow's key handling, and logs it for the on-screen badge.
    private static func press(_ label: String, _ chars: String, _ keyCode: UInt16, app: AppModel, window: NSWindow) {
        events.append(Event(t: elapsed, kind: "key", value: label))
        guard let e = NSEvent.keyEvent(with: .keyDown, location: .zero, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                       windowNumber: window.windowNumber, context: nil, characters: chars,
                                       charactersIgnoringModifiers: chars, isARepeat: false, keyCode: keyCode) else { return }
        _ = KeyCommands.handle(e, app: app)
    }

    private static func script(app: AppModel, window: NSWindow) async {
        let right: (String, UInt16) = ("\u{F703}", 124)
        func key(_ label: String, _ k: (String, UInt16)) { press(label, k.0, k.1, app: app, window: window) }

        // 1. Big previews: thumbnails grow with ⌘+.
        scene("grow")
        await wait(1.4)
        events.append(Event(t: elapsed, kind: "key", value: "⌘ +"))
        for size in stride(from: 150.0, through: 280.0, by: 5) {
            app.thumbnailSize = size
            await wait(0.03)
        }
        await wait(1.6)

        // 2. Cull with single keys.
        scene("cull")
        await wait(0.5)
        key("P", ("p", 35)); await wait(0.6)
        key("→", right); await wait(0.45)
        key("→", right); await wait(0.45)
        key("P", ("p", 35)); await wait(0.6)
        key("→", right); await wait(0.45)
        key("X", ("x", 7)); await wait(0.6)
        key("→", right); await wait(0.45)
        key("P", ("p", 35)); await wait(0.6)
        key("→", right); await wait(0.45)
        key("→", right); await wait(0.45)
        key("P", ("p", 35)); await wait(0.9)

        // 3. Look closer.
        scene("loupe")
        key("Space", (" ", 49)); await wait(1.8)
        key("→", right); await wait(1.0)
        key("P", ("p", 35)); await wait(1.4)
        key("Space", (" ", 49)); await wait(0.9)

        // 4. Import only the picks, verified.
        scene("import")
        events.append(Event(t: elapsed, kind: "key", value: "⌘ I"))
        app.openImport()
        await wait(2.4)
        events.append(Event(t: elapsed, kind: "key", value: "↩"))
        app.importFlow?.start()
        while app.importFlow?.phase == .copying { await wait(0.1) }

        // 5. Clear them off the card.
        scene("delete")
        await wait(2.2)
        app.importFlow?.deleteFromCard()
        while app.importFlow?.phase != .finished { await wait(0.1) }
        await wait(2.0)
        app.importFlow?.close()
        await wait(1.2)
    }

    /// Puts the window on the sharpest screen at a portrait-friendly size.
    private static func placeWindow() async -> NSWindow? {
        for _ in 0..<50 {
            if let w = NSApp.windows.first(where: { $0.isVisible && $0.contentView != nil && !($0 is NSPanel) }) {
                let screen = NSScreen.screens.max { $0.backingScaleFactor < $1.backingScaleFactor } ?? NSScreen.main!
                let size = NSSize(width: 1040, height: 1000)
                let v = screen.visibleFrame
                w.setFrame(NSRect(x: v.midX - size.width / 2, y: v.midY - size.height / 2, width: size.width, height: size.height), display: true)
                NSApp.activate()
                w.makeKeyAndOrderFront(nil)
                return w
            }
            await wait(0.1)
        }
        return nil
    }
}

/// Records every Winnow window (so sheets are included) inside the main window's frame.
final class WindowRecorder: NSObject, SCRecordingOutputDelegate, @unchecked Sendable {
    private var stream: SCStream?
    private var finished: CheckedContinuation<Void, Never>?

    @MainActor
    func start(window: NSWindow, to url: URL) async throws {
        try? FileManager.default.removeItem(at: url)
        var found: (SCDisplay, SCRunningApplication, NSScreen)?
        for _ in 0..<20 {
            let content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
            if let screen = window.screen,
               let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID,
               let display = content.displays.first(where: { $0.displayID == displayID }),
               let me = content.applications.first(where: { $0.processID == getpid() }) {
                found = (display, me, screen)
                break
            }
            print("DEMO waiting for capture content: screen=\(window.screen != nil) displays=\(content.displays.map(\.displayID)) mine=\(content.applications.contains { $0.processID == getpid() })")
            try await Task.sleep(for: .seconds(0.5))
        }
        guard let (display, me, screen) = found else {
            throw NSError(domain: "Demo", code: 1, userInfo: [NSLocalizedDescriptionKey: "Couldn't find the window's display"])
        }
        let filter = SCContentFilter(display: display, including: [me], exceptingWindows: [])
        let config = SCStreamConfiguration()
        let wf = window.frame, sf = screen.frame
        config.sourceRect = CGRect(x: wf.minX - sf.minX, y: sf.maxY - wf.maxY, width: wf.width, height: wf.height)
        config.width = Int(wf.width * screen.backingScaleFactor)
        config.height = Int(wf.height * screen.backingScaleFactor)
        config.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        config.showsCursor = false
        config.backgroundColor = .clear

        let output = SCRecordingOutputConfiguration()
        output.outputURL = url
        output.outputFileType = .mov
        output.videoCodecType = .hevc
        let stream = SCStream(filter: filter, configuration: config, delegate: nil)
        try stream.addRecordingOutput(SCRecordingOutput(configuration: output, delegate: self))
        try await stream.startCapture()
        self.stream = stream
    }

    func stop() async throws {
        await withCheckedContinuation { c in
            finished = c
            Task { try? await stream?.stopCapture() }
        }
    }

    func recordingOutputDidFinishRecording(_ recordingOutput: SCRecordingOutput) {
        finished?.resume()
        finished = nil
    }

    func recordingOutput(_ recordingOutput: SCRecordingOutput, didFailWithError error: Error) {
        print("DEMO recording error: \(error)")
        finished?.resume()
        finished = nil
    }
}
#endif
