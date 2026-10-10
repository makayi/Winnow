import AppKit

/// Single-key culling shortcuts. SwiftUI focus is unreliable for bare keys over a grid,
/// so this uses an AppKit local event monitor. Command-key shortcuts go through the menus.
@MainActor
final class KeyCommands {
    private var monitor: Any?

    enum Key: UInt16 {
        case returnKey = 36, space = 49, escape = 53, enter = 76
        case left = 123, right = 124, down = 125, up = 126
    }

    func install(app: AppModel) {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak app] event in
            guard let app else { return event }
            return MainActor.assumeIsolated { KeyCommands.handle(event, app: app) } ? nil : event
        }
    }

    static func handle(_ event: NSEvent, app: AppModel) -> Bool {
        if event.window is NSPanel { return false }  // open panels, alerts
        if let text = event.window?.firstResponder as? NSTextView, text.isEditable { return false }
        if !event.modifierFlags.intersection([.command, .control, .option]).isEmpty { return false }

        let key = Key(rawValue: event.keyCode)

        if let flow = app.importFlow {
            guard key == .escape else { return false }
            switch flow.phase {
            case .options, .finished: flow.close()
            case .asking: flow.keepOnCard()
            case .copying: break
            }
            return true
        }

        guard let session = app.session else { return false }
        let inLoupe = app.mode == .loupe

        switch key {
        case .left: session.moveSelection(by: -1); return true
        case .right: session.moveSelection(by: 1); return true
        case .up: if !inLoupe { session.moveSelection(by: -app.gridColumns) }; return true
        case .down: if !inLoupe { session.moveSelection(by: app.gridColumns) }; return true
        case .space: inLoupe ? app.closeLoupe() : app.openLoupe(); return true
        case .returnKey, .enter: if !inLoupe { app.openLoupe() }; return true
        case .escape: if inLoupe { app.closeLoupe() }; return true
        case nil: break
        }

        guard let id = session.selectedID else { return false }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "p": session.setFlag(.pick, for: id)
        case "x": session.setFlag(.reject, for: id)
        case "u": session.setFlag(.none, for: id)
        case "z": if inLoupe { app.zoomed.toggle() } else { return false }
        default: return false
        }
        return true
    }
}
