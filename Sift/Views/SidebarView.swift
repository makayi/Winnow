import SwiftUI

struct SidebarView: View {
    @Environment(AppModel.self) private var app
    let session: CardSession

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            SourceCard(session: session)

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if app.sources.count > 1 {
                        section("Sources") {
                            ForEach(app.sources) { source in
                                SidebarRow(icon: source.isCard ? "sdcard" : "folder", title: source.name, count: nil,
                                           selected: source == session.source) { app.open(source) }
                            }
                        }
                    }

                    section("Folders") {
                        ForEach(session.folders, id: \.name) { folder in
                            SidebarRow(icon: "folder", title: folder.name, count: folder.count,
                                       selected: session.folderFilter == folder.name) {
                                session.folderFilter = session.folderFilter == folder.name ? nil : folder.name
                            }
                        }
                    }

                    section("Show") {
                        ForEach(PhotoFilter.allCases, id: \.self) { filter in
                            SidebarRow(icon: filter.symbol, iconColor: color(for: filter), title: filter.title,
                                       count: session.count(filter), selected: session.filter == filter) {
                                session.filter = filter
                            }
                        }
                    }
                }
            }
            .scrollIndicators(.never)

            Text("RAF and JPG pairs are shown as one photo. Both files import together.")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 6)
        }
        .padding(.horizontal, 12)
        .padding(.top, 44)  // clear of the window's traffic lights
        .padding(.bottom, 16)
        .frame(maxHeight: .infinity, alignment: .top)
        .siftGlass(.regular, in: RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
    }

    private func color(for filter: PhotoFilter) -> Color {
        switch filter {
        case .picks: Theme.pick
        case .rejects: Theme.reject
        default: Theme.textSecondary
        }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .padding(.horizontal, 8)
                .padding(.bottom, 4)
            content()
        }
    }
}

private struct SourceCard: View {
    @Environment(AppModel.self) private var app
    let session: CardSession

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: session.source.isCard ? "sdcard" : "folder")
                .font(.system(size: 15))
                .frame(width: 30, height: 30)
                .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(session.cameraName)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Text(detail)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if app.canEject {
                Button { app.ejectCurrent() } label: {
                    Image(systemName: "eject")
                        .font(.system(size: 11, weight: .semibold))
                }
                .buttonStyle(.glass)
                .controlSize(.small)
                .buttonBorderShape(.circle)
                .help("Eject card (⌘E)")
                .accessibilityLabel("Eject card")
            }
        }
        .padding(10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var detail: String {
        let kind = session.source.isCard ? "SD card" : "Folder"
        if session.isEjected { return "\(kind) · ejected" }
        if session.isScanning { return "\(kind) · reading…" }
        return "\(kind) · \(Format.plural(session.photos.count, "photo"))"
    }
}

private struct SidebarRow: View {
    let icon: String
    var iconColor: Color = Theme.textSecondary
    let title: String
    let count: Int?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(iconColor)
                    .frame(width: 18)
                Text(title)
                    .font(.system(size: 13))
                    .lineLimit(1)
                Spacer(minLength: 4)
                if let count {
                    Text("\(count)")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(.horizontal, 8)
            .frame(height: 30)
            .background(selected ? Color.white.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
