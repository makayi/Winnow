import AppKit
import SwiftUI

struct LoupeView: View {
    @Environment(AppModel.self) private var app
    let session: CardSession

    @State private var image: CGImage?
    @State private var imageID: String?
    @State private var full: CGImage?
    @State private var fullID: String?

    var body: some View {
        let photo = session.selected
        let display = photo.flatMap { p in
            (imageID == p.id ? image : nil) ?? session.previews.bestCached(p.id, preferring: PreviewLoader.loupePixels)
        }

        ZStack {
            Theme.loupeBackground.ignoresSafeArea()

            // A heavily blurred glow of the photo itself.
            // Overlay on a clear view so the filled image can't grow the layout past the window.
            Color.clear
                .overlay {
                    if let display {
                        Image(decorative: display, scale: 1)
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                            .blur(radius: 120)
                            .opacity(0.4)
                    }
                }
                .clipped()
                .ignoresSafeArea()
                .allowsHitTesting(false)

            HStack(spacing: 16) {
                VStack(spacing: 14) {
                    topBar(photo)
                    ZStack {
                        photoArea(photo: photo, display: display)
                            .padding(.horizontal, 64)
                        HStack {
                            navButton("chevron.left", label: "Previous photo") { session.moveSelection(by: -1) }
                            Spacer()
                            navButton("chevron.right", label: "Next photo") { session.moveSelection(by: 1) }
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    FilmstripView(session: session)
                }
                if let photo {
                    InspectorView(session: session, photo: photo)
                        .frame(width: 300)
                }
            }
            .padding(16)
        }
        .task(id: photo?.id) {
            guard let photo else { return }
            if let loaded = await session.previews.loupeImage(for: photo), !Task.isCancelled {
                image = loaded
                imageID = photo.id
            }
            // Prefetch the next 2 and previous 1.
            if let i = session.selectedIndex {
                let v = session.visible
                let neighbours = [i + 1, i + 2, i - 1].filter { v.indices.contains($0) }.map { v[$0] }
                session.previews.prefetchLoupe(neighbours)
            }
        }
        .task(id: app.zoomed ? photo?.id : nil) {
            guard app.zoomed, let photo, fullID != photo.id else { return }
            full = nil
            if let decoded = await session.previews.fullResolution(for: photo), !Task.isCancelled {
                full = decoded
                fullID = photo.id
            }
        }
    }

    // MARK: Pieces

    private func topBar(_ photo: Photo?) -> some View {
        @Bindable var app = app
        return ZStack {
            HStack {
                Button { app.closeLoupe() } label: {
                    Label("Grid", systemImage: "square.grid.2x2")
                        .padding(.horizontal, 2)
                }
                .buttonStyle(.glass)
                .controlSize(.large)
                .help("Back to grid (Space)")
                Spacer()
                Picker("Zoom", selection: $app.zoomed) {
                    Text("Fit").tag(false)
                    Text("100%").tag(true)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 130)
                .controlSize(.large)
                .help("Toggle 100% (Z)")
            }
            if let photo {
                HStack(spacing: 8) {
                    Text(photo.basename)
                        .font(.system(size: 13, weight: .semibold))
                    Text("/")
                        .foregroundStyle(Theme.textTertiary)
                    Text("\((session.selectedIndex ?? 0) + 1) of \(session.visible.count) · \(photo.kindLabelSpaced)")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                        .monospacedDigit()
                }
                .padding(.horizontal, 18)
                .frame(height: 36)
                .siftGlass(.regular, in: .capsule)
            }
        }
        .padding(.leading, 70)  // clear of the traffic lights
    }

    @ViewBuilder
    private func photoArea(photo: Photo?, display: CGImage?) -> some View {
        if app.zoomed, let photo {
            Group {
                if let full, fullID == photo.id {
                    ScrollView([.horizontal, .vertical]) {
                        Image(decorative: full, scale: NSScreen.main?.backingScaleFactor ?? 2)
                    }
                    .defaultScrollAnchor(.center)
                } else {
                    VStack(spacing: 10) {
                        ProgressView()
                        Text(photo.raf != nil ? "Decoding RAW…" : "Loading full size…")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        } else if let display {
            Image(decorative: display, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .shadow(color: .black.opacity(0.6), radius: 40, y: 18)
                .opacity(session.flag(photo?.id ?? "") == .reject ? 0.6 : 1)
                .accessibilityLabel(photo.map { "\($0.basename), \(session.flag($0.id).accessibilityName)" } ?? "")
        } else {
            ProgressView()
        }
    }

    private func navButton(_ symbol: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .semibold))
                .frame(width: 30, height: 30)
        }
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .controlSize(.large)
        .accessibilityLabel(label)
    }
}

struct InspectorView: View {
    let session: CardSession
    let photo: Photo

    var body: some View {
        let flag = session.flag(photo.id)
        let exif = session.exif[photo.id]
        VStack(alignment: .leading, spacing: 18) {
            VStack(spacing: 8) {
                flagButton(.pick, title: "Pick", symbol: "flag.fill", key: "P", color: Theme.pick, current: flag)
                flagButton(.reject, title: "Reject", symbol: "xmark", key: "X", color: Theme.reject, current: flag)
            }

            Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                GridRow {
                    tile("Shutter", exif?.shutterText)
                    tile("Aperture", exif?.apertureText)
                }
                GridRow {
                    tile("ISO", exif?.iso.map(String.init))
                    tile("Focal", exif?.focalText)
                }
            }

            VStack(spacing: 0) {
                row("Camera", exif?.camera)
                row("Lens", exif?.lens)
                row("Film simulation", exif.map { $0.filmSimulation ?? "Unknown" })
                row("Taken", (exif?.dateTaken).map { Format.takenFormatter.string(from: $0) })
                row("Size", [photo.rafSize, photo.jpgSize].filter { $0 > 0 }.map(Format.roundBytes).joined(separator: " + "), last: true)
            }

            Spacer(minLength: 0)

            Text("← → next photo · Space back to grid · Z zoom to 100%")
                .font(.system(size: 11))
                .foregroundStyle(Theme.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(18)
        .padding(.top, 4)
        .frame(maxHeight: .infinity, alignment: .top)
        .siftGlass(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
        .task(id: photo.id) { await session.ensureExif(for: photo) }
    }

    private func flagButton(_ flag: Flag, title: String, symbol: String, key: String, color: Color, current: Flag) -> some View {
        let active = current == flag
        return Button {
            session.setFlag(active ? .none : flag, for: photo.id)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(active ? Theme.onPick : color)
                Text(active ? (flag == .pick ? "Picked" : "Rejected") : title)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                KeyCap(key)
                    .foregroundStyle(active ? Theme.onPick : Theme.textSecondary)
            }
            .foregroundStyle(active ? Theme.onPick : Theme.textPrimary)
            .padding(.horizontal, 14)
            .frame(height: 38)
            .background(active ? color : Color.white.opacity(0.08), in: .capsule)
            .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(active ? "On" : "Off")
    }

    private func tile(_ label: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(Theme.textSecondary)
            Text(value ?? "—")
                .font(.system(size: 17, weight: .semibold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
    }

    private func row(_ label: String, _ value: String?, last: Bool = false) -> some View {
        VStack(spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(label)
                    .foregroundStyle(Theme.textSecondary)
                Spacer(minLength: 12)
                Text(value ?? "—")
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
            }
            .font(.system(size: 12.5))
            .padding(.vertical, 8)
            if !last { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }
}

struct FilmstripView: View {
    let session: CardSession

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                LazyHStack(spacing: 8) {
                    ForEach(session.visible) { photo in
                        FilmThumb(photo: photo, flag: session.flag(photo.id), current: photo.id == session.selectedID,
                                  previews: session.previews)
                            .id(photo.id)
                            .onTapGesture { session.selectedID = photo.id }
                    }
                }
                .padding(10)
            }
            .scrollIndicators(.never)
            .frame(height: 84)
            .siftGlass(.regular, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onAppear {
                if let id = session.selectedID { proxy.scrollTo(id, anchor: .center) }
            }
            .onChange(of: session.selectedID) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }
}

struct FilmThumb: View {
    let photo: Photo
    let flag: Flag
    let current: Bool
    let previews: PreviewLoader
    var width: CGFloat = 96
    var height: CGFloat = 64

    @State private var loaded: CGImage?

    var body: some View {
        let bucket = PreviewLoader.buckets[0]
        let image = loaded ?? previews.bestCached(photo.id, preferring: bucket)
        ZStack {
            Color.white.opacity(0.06)
            if let image {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            }
        }
        .frame(width: width, height: height)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .opacity(flag == .reject && !current ? 0.38 : 1)
        .overlay {
            if current {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(.white, lineWidth: 2.5)
            } else if flag == .pick {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Theme.pick, lineWidth: 2.5)
            }
        }
        .task {
            if loaded == nil { loaded = await previews.thumbnail(for: photo, bucket: bucket) }
        }
        .accessibilityElement()
        .accessibilityLabel("\(photo.basename), \(flag.accessibilityName)")
    }
}
