import AppKit
import SwiftUI

struct GridView: View {
    @Environment(AppModel.self) private var app
    let session: CardSession
    let leadingInset: CGFloat

    private let topInset: CGFloat = 76
    private let bottomInset: CGFloat = 84
    private let trailingInset: CGFloat = 20

    /// Remembers a click that cycled a flag, so the second click of a double-click can undo it.
    @State private var lastCycle: (id: String, previous: Flag)?

    var body: some View {
        GeometryReader { geo in
            let available = max(geo.size.width - leadingInset - trailingInset, Theme.minThumb)
            let size = app.thumbnailSize
            let columns = max(1, Int((available + Theme.gridSpacingH) / (size + Theme.gridSpacingH)))
            let cellWidth = (available - CGFloat(columns - 1) * Theme.gridSpacingH) / CGFloat(columns)
            let bucket = PreviewLoader.bucket(forPixels: cellWidth * 2)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVGrid(
                        columns: Array(repeating: GridItem(.flexible(), spacing: Theme.gridSpacingH, alignment: .top), count: columns),
                        spacing: Theme.gridSpacingV
                    ) {
                        ForEach(session.visible) { photo in
                            ThumbnailCell(
                                photo: photo,
                                flag: session.flag(photo.id),
                                imported: session.isImported(photo),
                                selected: photo.id == session.selectedID,
                                exposure: session.exif[photo.id]?.exposureLine,
                                bucket: bucket,
                                previews: session.previews
                            )
                            .id(photo.id)
                            .onTapGesture { click(photo) }
                            .accessibilityAction { session.selectedID = photo.id }
                            .accessibilityAction(named: "Pick") { session.setFlag(.pick, for: photo.id) }
                            .accessibilityAction(named: "Reject") { session.setFlag(.reject, for: photo.id) }
                            .accessibilityAction(named: "Clear flag") { session.setFlag(.none, for: photo.id) }
                            .accessibilityAction(named: "View large") {
                                session.selectedID = photo.id
                                app.openLoupe()
                            }
                        }
                    }
                    .padding(.leading, leadingInset)
                    .padding(.trailing, trailingInset)
                    .padding(.top, topInset)
                    .padding(.bottom, bottomInset)

                    if session.visible.isEmpty && !session.isScanning {
                        emptyMessage
                            .padding(.leading, leadingInset)
                            .padding(.top, 80)
                    }
                }
                .scrollIndicators(.automatic)
                .onChange(of: session.selectedID) { _, id in
                    guard let id, app.mode == .grid else { return }
                    withAnimation(.easeOut(duration: 0.12)) { proxy.scrollTo(id) }
                }
                .onChange(of: app.mode) { _, mode in
                    // Returning from the loupe: keep the photo you were on in view.
                    if mode == .grid, let id = session.selectedID { proxy.scrollTo(id, anchor: .center) }
                }
                .onChange(of: columns, initial: true) { _, c in app.gridColumns = c }
            }
        }
    }

    private var emptyMessage: some View {
        VStack(spacing: 8) {
            Text(session.scanError ?? (session.photos.isEmpty ? "No photos found" : "Nothing to show"))
                .font(.system(size: 15, weight: .semibold))
            Text(session.photos.isEmpty ? "Sift looks for RAF, JPG and HEIF files." : "No photos match \(session.filter.title.lowercased()).")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textSecondary)
        }
        .frame(maxWidth: .infinity)
    }

    /// Click selects; clicking the selected photo cycles its flag; double-click opens it large.
    private func click(_ photo: Photo) {
        let clicks = NSApp.currentEvent?.clickCount ?? 1
        if clicks >= 2 {
            if let last = lastCycle, last.id == photo.id { session.setFlag(last.previous, for: photo.id) }
            lastCycle = nil
            session.selectedID = photo.id
            app.openLoupe()
            return
        }
        if session.selectedID == photo.id {
            let previous = session.flag(photo.id)
            session.setFlag(previous.cycled, for: photo.id)
            lastCycle = (photo.id, previous)
        } else {
            session.selectedID = photo.id
            lastCycle = nil
        }
    }
}

struct ThumbnailCell: View {
    let photo: Photo
    let flag: Flag
    let imported: Bool
    let selected: Bool
    let exposure: String?
    let bucket: Int
    let previews: PreviewLoader

    @State private var loaded: CGImage?

    var body: some View {
        let image = loaded ?? previews.bestCached(photo.id, preferring: bucket)
        VStack(alignment: .leading, spacing: 7) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                    .fill(Color.white.opacity(0.045))
                if let image {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous))
                        .shadow(color: .black.opacity(0.45), radius: 10, y: 5)
                }
            }
            .aspectRatio(3 / 2, contentMode: .fit)
            .opacity(flag == .reject ? 0.38 : 1)
            .overlay {
                if flag == .pick {
                    RoundedRectangle(cornerRadius: Theme.Radius.thumb, style: .continuous)
                        .strokeBorder(Theme.pick, lineWidth: 3)
                }
            }
            .overlay(alignment: .topLeading) { badge.padding(8) }
            .overlay(alignment: .topTrailing) {
                if imported {
                    Text("Imported")
                        .font(.system(size: 10.5, weight: .semibold))
                        .padding(.horizontal, 9)
                        .padding(.vertical, 4)
                        .siftGlass(.regular, in: .capsule)
                        .padding(8)
                }
            }
            .padding(4)
            .overlay {
                if selected {
                    RoundedRectangle(cornerRadius: Theme.Radius.thumb + 4, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.9), lineWidth: 2)
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(photo.basename)
                        .font(.system(size: 12.5, weight: .medium))
                        .lineLimit(1)
                    Spacer(minLength: 4)
                    Text(photo.kindLabel)
                        .font(.system(size: 10.5, weight: .semibold))
                        .foregroundStyle(Theme.textSecondary)
                }
                Text(exposure ?? " ")
                    .font(.system(size: 11.5))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .opacity(flag == .reject ? 0.38 : 1)
        }
        .contentShape(Rectangle())
        .task(id: bucket) {
            if let hit = previews.cached(photo.id, size: bucket) {
                loaded = hit
                return
            }
            if let image = await previews.thumbnail(for: photo, bucket: bucket), !Task.isCancelled {
                loaded = image
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(photo.basename), \(flag.accessibilityName)\(imported ? ", imported" : "")")
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var badge: some View {
        switch flag {
        case .pick:
            FlagBadge(symbol: "flag.fill", color: Theme.pick)
        case .reject:
            FlagBadge(symbol: "xmark", color: Theme.reject)
        case .none:
            EmptyView()
        }
    }
}

struct FlagBadge: View {
    let symbol: String
    let color: Color

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(color)
            .frame(width: 26, height: 26)
            .siftGlass(.regular.tint(color.opacity(0.18)), in: .circle)
    }
}
