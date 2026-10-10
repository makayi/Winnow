import SwiftUI

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        ZStack {
            Theme.windowBackground.ignoresSafeArea()
            if let session = app.session {
                BrowseView(session: session)
                    .blur(radius: app.importFlow != nil ? 22 : 0)
                if app.mode == .loupe, app.importFlow == nil {
                    LoupeView(session: session)
                        .transition(.opacity)
                }
                if let flow = app.importFlow {
                    ImportOverlay(flow: flow)
                        .transition(.opacity.combined(with: .scale(scale: 0.98)))
                }
            } else {
                EmptyStateView()
            }
        }
        .animation(.easeOut(duration: 0.18), value: app.mode)
        .animation(.easeOut(duration: 0.2), value: app.importFlow == nil)
        .frame(minWidth: 1000, minHeight: 680)
        .preferredColorScheme(.dark)
        .foregroundStyle(Theme.textPrimary)
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
        VStack(spacing: 14) {
            Image(systemName: "sdcard")
                .font(.system(size: 40, weight: .light))
                .foregroundStyle(Theme.textSecondary)
                .padding(.bottom, 4)
            Text("Insert an SD card")
                .font(.system(size: 18, weight: .semibold))
            Text("Sift opens your camera's card as soon as it mounts.\nYou can also browse any folder of photos.")
                .font(.system(size: 13))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
            Button("Open Folder…") { app.openFolderPanel() }
                .buttonStyle(.glassProminent)
                .tint(Theme.pick)
                .foregroundStyle(Theme.onPick)
                .controlSize(.large)
                .padding(.top, 6)
        }
        .padding(40)
        .siftGlass(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
    }
}
