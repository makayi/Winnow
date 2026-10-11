import SwiftUI

/// The detail column: the grid or the loupe, with the toolbar and inspector for each.
struct BrowseView: View {
    @Environment(AppModel.self) private var app
    let session: CardSession

    var body: some View {
        @Bindable var app = app
        Group {
            if app.mode == .loupe {
                LoupeView(session: session)
            } else {
                GridView(session: session)
            }
        }
        .navigationTitle(title)
        .navigationSubtitle(subtitle)
        .toolbar {
            if app.mode == .loupe {
                LoupeToolbar(session: session)
            } else {
                GridToolbar(session: session)
            }
        }
    }

    private var title: String {
        if app.mode == .loupe, let photo = session.selected { return photo.basename }
        if let folder = session.folderFilter { return folder }
        if session.filter != .all { return session.filter.title }
        let folders = session.folders
        return folders.count == 1 ? folders[0].name : session.source.name
    }

    private var subtitle: String {
        if session.isScanning { return "Reading card…" }
        if app.mode == .loupe, let photo = session.selected {
            return "\((session.selectedIndex ?? 0) + 1) of \(session.visible.count) · \(photo.kindLabelSpaced)"
        }
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
}

private struct GridToolbar: ToolbarContent {
    @Environment(AppModel.self) private var app
    let session: CardSession

    var body: some ToolbarContent {
        @Bindable var app = app
        let picks = session.picks.count

        ToolbarItem {
            Slider(value: $app.thumbnailSize, in: Theme.minThumb...Theme.maxThumb) {
                Text("Thumbnail size")
            } minimumValueLabel: {
                Image(systemName: "square").imageScale(.small)
            } maximumValueLabel: {
                Image(systemName: "square").imageScale(.large)
            }
            .frame(width: 180)
            .help("Thumbnail size (⌘= / ⌘-)")
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button("View large", systemImage: "arrow.up.left.and.arrow.down.right") { app.openLoupe() }
                .disabled(session.selected == nil)
                .help("View large (Space)")
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button {
                app.openImport()
            } label: {
                Label(picks > 0 ? "Import \(Format.plural(picks, "pick"))" : "Import picks", systemImage: "square.and.arrow.down")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(.glassProminent)
            .tint(Theme.pick)
            .foregroundStyle(Theme.onPick)
            .disabled(!app.canImport)
            .help("Import picks (⌘I)")
        }
    }
}

private struct LoupeToolbar: ToolbarContent {
    @Environment(AppModel.self) private var app
    let session: CardSession

    var body: some ToolbarContent {
        @Bindable var app = app

        ToolbarItem(placement: .navigation) {
            Button("Grid", systemImage: "square.grid.2x2") { app.closeLoupe() }
                .labelStyle(.titleAndIcon)
                .help("Back to grid (Space)")
        }

        ToolbarItem {
            Picker("Zoom", selection: $app.zoomed) {
                Text("Fit").tag(false)
                Text("100%").tag(true)
            }
            .pickerStyle(.segmented)
            .help("Toggle 100% (Z)")
        }

        ToolbarSpacer(.fixed)

        ToolbarItem {
            Button("Info", systemImage: "info.circle") { app.toggleInspector() }
                .help("Show or hide photo info")
        }
    }
}

/// Floating key hints at the bottom of the grid.
struct BottomPill: View {
    let session: CardSession

    var body: some View {
        HStack(spacing: 14) {
            hint("P", "pick")
            hint("X", "reject")
            hint("U", "clear")
            hint("Space", "view large")
            Divider().frame(height: 16)
            HStack(spacing: 5) {
                Image(systemName: "flag.fill").foregroundStyle(Theme.pickInk).font(.system(size: 10))
                Text("\(session.picks.count) picked")
            }
            HStack(spacing: 5) {
                Image(systemName: "xmark").foregroundStyle(Theme.rejectInk).font(.system(size: 10, weight: .bold))
                Text("\(session.rejects.count) rejected")
            }
        }
        .font(.system(size: 12))
        .monospacedDigit()
        .padding(.horizontal, 18)
        .frame(height: 40)
        .winnowGlass(.regular, in: .capsule)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            KeyCap(key)
            Text(label).foregroundStyle(.secondary)
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
            .background(.quaternary, in: RoundedRectangle(cornerRadius: 5, style: .continuous))
    }
}
