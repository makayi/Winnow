import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    let session: CardSession

    var body: some View {
        @Bindable var session = session
        List(selection: $session.sidebarSelection) {
            Section {
                SourceRow(session: session)
            }

            if app.sources.count > 1 {
                Section("Sources") {
                    ForEach(app.sources) { source in
                        Button { app.open(source) } label: {
                            Label(source.name, systemImage: source.isCard ? "sdcard" : "folder")
                                .fontWeight(source == session.source ? .semibold : .regular)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Section("Folders") {
                ForEach(session.folders, id: \.name) { folder in
                    Label(folder.name, systemImage: "folder")
                        .badge(folder.count)
                        .tag(SidebarItem.folder(folder.name))
                }
            }

            Section("Show") {
                ForEach(PhotoFilter.allCases, id: \.self) { filter in
                    Label {
                        Text(filter.title)
                    } icon: {
                        Image(systemName: filter.symbol)
                            .foregroundStyle(color(for: filter))
                    }
                    .badge(session.count(filter))
                    .tag(SidebarItem.filter(filter))
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Text("RAF and JPG pairs are shown as one photo. Both files import together.")
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
        }
    }

    private func color(for filter: PhotoFilter) -> Color {
        switch filter {
        case .picks: Theme.pickInk
        case .rejects: Theme.rejectInk
        default: .secondary
        }
    }
}

private struct SourceRow: View {
    @Environment(AppModel.self) private var app
    let session: CardSession

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: session.source.isCard ? "sdcard" : "folder")
                .font(.system(size: 15))
                .foregroundStyle(.secondary)
                .frame(width: 30, height: 30)
                .background(.quaternary, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 1) {
                Text(session.cameraName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if app.canEject {
                Button { app.ejectCurrent() } label: {
                    Image(systemName: "eject.fill")
                }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .help("Eject card (⌘E)")
                .accessibilityLabel("Eject card")
            }
        }
        .padding(.vertical, 4)
        .selectionDisabled()
    }

    private var detail: String {
        let kind = session.source.isCard ? "SD card" : "Folder"
        if session.isEjected { return "\(kind) · ejected" }
        if session.isScanning { return "\(kind) · reading…" }
        return "\(kind) · \(Format.plural(session.photos.count, "photo"))"
    }
}
