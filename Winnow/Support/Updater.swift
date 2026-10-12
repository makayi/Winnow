import Sparkle
import SwiftUI

/// Sparkle updates: checks the appcast daily, and on demand from the Winnow menu.
@MainActor
final class Updater {
    static let shared = Updater()

    private let controller: SPUStandardUpdaterController

    private init() {
        #if DEBUG
        // Debug builds aren't signed for release, so don't let them update themselves.
        controller = SPUStandardUpdaterController(startingUpdater: false, updaterDelegate: nil, userDriverDelegate: nil)
        #else
        controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        #endif
    }

    var canCheck: Bool { controller.updater.canCheckForUpdates }

    func checkForUpdates() { controller.checkForUpdates(nil) }
}

struct CheckForUpdatesCommand: Commands {
    var body: some Commands {
        CommandGroup(after: .appInfo) {
            Button("Check for Updates…") { Updater.shared.checkForUpdates() }
        }
    }
}
