import SwiftUI

struct BrowseView: View {
    @Environment(AppModel.self) private var app
    let session: CardSession

    static let sidebarPadding: CGFloat = 10
    static var contentLeading: CGFloat { Theme.sidebarWidth + sidebarPadding * 2 + 10 }

    var body: some View {
        ZStack(alignment: .topLeading) {
            GridView(session: session, leadingInset: Self.contentLeading)

            // Drag strip so the window can be moved by its top edge.
            Color.clear
                .frame(height: 64)
                .contentShape(Rectangle())
                .gesture(WindowDragGesture())

            TopBar(session: session)
                .padding(.leading, Self.contentLeading)
                .padding(.trailing, 16)
                .padding(.top, 12)

            SidebarView(session: session)
                .frame(width: Theme.sidebarWidth)
                .frame(maxHeight: .infinity)
                .padding(Self.sidebarPadding)

            BottomPill(session: session)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .padding(.leading, Self.contentLeading - 10)
                .padding(.bottom, 18)
        }
        .ignoresSafeArea()
    }
}

private struct TopBar: View {
    @Environment(AppModel.self) private var app
    let session: CardSession

    var title: String {
        if let folder = session.folderFilter { return folder }
        let folders = session.folders
        return folders.count == 1 ? folders[0].name : session.source.name
    }

    var subtitle: String {
        let photos = session.visible
        var parts = [Format.plural(photos.count, "photo")]
        if let first = photos.first, let last = photos.last {
            let a = session.exif[first.id]?.dateTaken ?? first.fileDate
            let b = session.exif[last.id]?.dateTaken ?? last.fileDate
            let fa = Format.dayFormatter.string(from: a), fb = Format.dayFormatter.string(from: b)
            parts.append(fa == fb ? fa : "\(fa) – \(fb)")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        @Bindable var app = app
        let picks = session.picks.count
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                Text(session.isScanning ? "Reading card…" : subtitle)
                    .font(.system(size: 11))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
            .padding(.horizontal, 18)
            .frame(height: 44)
            .siftGlass(.regular, in: .capsule)

            Spacer(minLength: 12)

            HStack(spacing: 10) {
                Image(systemName: "square")
                    .font(.system(size: 9, weight: .semibold))
                Slider(value: $app.thumbnailSize, in: Theme.minThumb...Theme.maxThumb)
                    .frame(width: 150)
                    .accessibilityLabel("Thumbnail size")
                Image(systemName: "square")
                    .font(.system(size: 15, weight: .semibold))
            }
            .foregroundStyle(Theme.textSecondary)
            .padding(.horizontal, 16)
            .frame(height: 44)
            .siftGlass(.regular, in: .capsule)

            GlassEffectContainer(spacing: 8) {
                HStack(spacing: 8) {
                    Button { app.openLoupe() } label: {
                        Label("View large", systemImage: "arrow.up.left.and.arrow.down.right")
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glass)
                    .disabled(session.selected == nil)

                    Button { app.openImport() } label: {
                        Label(picks > 0 ? "Import \(Format.plural(picks, "pick"))" : "Import picks",
                              systemImage: "square.and.arrow.down")
                            .fontWeight(.semibold)
                            .padding(.horizontal, 4)
                    }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.pick)
                    .foregroundStyle(Theme.onPick)
                    .disabled(!app.canImport)
                    .help("Import picks (⌘I)")
                }
                .controlSize(.extraLarge)
            }
        }
    }
}

private struct BottomPill: View {
    let session: CardSession

    var body: some View {
        HStack(spacing: 14) {
            hint("P", "pick")
            hint("X", "reject")
            hint("U", "clear")
            hint("Space", "view large")
            Rectangle().fill(Theme.hairline).frame(width: 1, height: 16)
            HStack(spacing: 5) {
                Image(systemName: "flag.fill").foregroundStyle(Theme.pick).font(.system(size: 10))
                Text("\(session.picks.count) picked")
            }
            HStack(spacing: 5) {
                Image(systemName: "xmark").foregroundStyle(Theme.reject).font(.system(size: 10, weight: .bold))
                Text("\(session.rejects.count) rejected")
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(.horizontal, 18)
        .frame(height: 40)
        .siftGlass(.regular, in: .capsule)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(key)
            Text(label).foregroundStyle(Theme.textSecondary)
        }
    }
}

struct KeyCap: View {
    let key: String
    init(_ key: String) { self.key = key }

    var body: some View {
        Text(key)
            .font(.system(size: 10.5, weight: .semibold, design: .rounded))
            .padding(.horizontal, 5)
            .frame(minWidth: 18, minHeight: 17)
            .background(Color.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
