import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        Group {
            if let session = app.session {
                NavigationSplitView(columnVisibility: $app.columnVisibility) {
                    SidebarView(session: session)
                        .navigationSplitViewColumnWidth(min: 220, ideal: 240, max: 320)
                } detail: {
                    BrowseView(session: session)
                }
                .inspector(isPresented: $app.inspectorPresented) {
                    Group {
                        if let photo = session.selected {
                            InspectorView(session: session, photo: photo)
                        }
                    }
                    .inspectorColumnWidth(min: 270, ideal: 300, max: 380)
                }
            } else {
                EmptyStateView()
            }
        }
        .frame(minWidth: 860, minHeight: 680)
        .sheet(item: $app.importFlow, onDismiss: { app.leaveEjectedSession() }) { flow in
            ImportSheetContainer(flow: flow)
                .environment(app)
        }
        .alert("Couldn't eject", isPresented: Binding(get: { app.ejectError != nil }, set: { if !$0 { app.ejectError = nil } })) {
            Button("OK") { app.ejectError = nil }
        } message: {
            Text(app.ejectError ?? "")
        }
    }
}

struct EmptyStateView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ContentUnavailableView {
            Label("Insert an SD card", systemImage: "sdcard")
        } description: {
            Text("Winnow opens your camera's card as soon as it mounts.\nYou can also browse any folder of photos.")
        } actions: {
            Button("Open Folder…") { app.openFolderPanel() }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
        }
        .toolbar {
            ToolbarItem {
                Button("Open Folder…", systemImage: "folder") { app.openFolderPanel() }
            }
        }
    }
}
