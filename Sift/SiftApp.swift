import SwiftUI

@main
struct SiftApp: App {
    @State private var app = AppModel()
    @State private var keys = KeyCommands()

    var body: some Scene {
        Window("Sift", id: "main") {
            RootView()
                .environment(app)
                .onAppear {
                    keys.install(app: app)
                    #if DEBUG
                    DebugSnapshots.runIfRequested(app: app)
                    #endif
                }
        }
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1440, height: 900)
        .commands { SiftCommands(app: app) }
    }
}

struct SiftCommands: Commands {
    let app: AppModel

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("Open Folder…") { app.openFolderPanel() }
                .keyboardShortcut("o")
        }
        CommandGroup(replacing: .textEditing) {}
        CommandGroup(before: .toolbar) {
            Button("Bigger Thumbnails") { app.biggerThumbnails() }
                .keyboardShortcut("=")
            Button("Smaller Thumbnails") { app.smallerThumbnails() }
                .keyboardShortcut("-")
            Divider()
        }
        CommandMenu("Card") {
            Button("Import Picks…") { app.openImport() }
                .keyboardShortcut("i")
                .disabled(!app.canImport)
            Button("Eject Card") { app.ejectCurrent() }
                .keyboardShortcut("e")
                .disabled(!app.canEject)
        }
    }
}
