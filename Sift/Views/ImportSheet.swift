import SwiftUI

/// Glass sheet floating over a blurred copy of the grid.
struct ImportOverlay: View {
    let flow: ImportFlow

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture {}
            Group {
                if flow.phase == .options {
                    ImportSheet(flow: flow)
                } else {
                    ImportProgressView(flow: flow)
                }
            }
            .padding(28)
            .frame(maxWidth: 620)
            .siftGlass(.regular.tint(Color.black.opacity(0.2)), in: RoundedRectangle(cornerRadius: Theme.Radius.sheet, style: .continuous))
            .padding(40)
        }
    }
}

struct ImportSheet: View {
    @Bindable var flow: ImportFlow

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            header

            SheetSection("Destination") {
                HStack(spacing: 10) {
                    Image(systemName: "folder")
                        .foregroundStyle(Theme.textSecondary)
                    Text(Format.abbreviatedPath(flow.options.destinationPath))
                        .font(Theme.mono)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer(minLength: 8)
                    Button("Choose…") { flow.chooseDestination() }
                        .buttonStyle(.glass)
                }
                .padding(.leading, 14)
                .padding(5)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            }

            SheetSection("Folders") {
                VStack(spacing: 0) {
                    ForEach(Array(FolderLayout.allCases.enumerated()), id: \.element) { index, layout in
                        layoutRow(layout)
                        if index < FolderLayout.allCases.count - 1 {
                            Rectangle().fill(Theme.hairline).frame(height: 1).padding(.leading, 40)
                        }
                    }
                }
                .padding(4)
                .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: Theme.Radius.small, style: .continuous))
            }

            SheetSection("Files") {
                Picker("Files", selection: $flow.options.fileTypes) {
                    ForEach(FileTypeChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .controlSize(.large)
            }

            SheetSection("After copying") {
                VStack(alignment: .leading, spacing: 9) {
                    HStack(spacing: 6) {
                        Toggle("Verify every copy", isOn: .constant(true))
                            .disabled(true)
                        Text("Always on")
                            .font(.system(size: 11))
                            .foregroundStyle(Theme.textTertiary)
                    }
                    Toggle("Mark as imported", isOn: $flow.options.markImported)
                    if flow.lightroomInstalled {
                        Toggle("Open folder in Lightroom", isOn: $flow.options.openInLightroom)
                    }
                    if flow.session.source.isCard {
                        Toggle("Eject card when done", isOn: $flow.options.ejectWhenDone)
                    }
                }
                .toggleStyle(.checkbox)
                .font(.system(size: 13))
            }

            if let preview = flow.firstFilePreview {
                Text("\(Text("First file will be saved as ").foregroundStyle(Theme.textSecondary))\(Text(preview).font(Theme.mono))")
                    .font(.system(size: 12))
                    .lineLimit(2)
                    .truncationMode(.middle)
            }

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { flow.close() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.cancelAction)
                Button {
                    flow.start()
                } label: {
                    Text("Import \(Format.plural(flow.photos.count, "photo"))")
                        .fontWeight(.semibold)
                        .padding(.horizontal, 6)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.pick)
                .foregroundStyle(Theme.onPick)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.extraLarge)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(Array(flow.photos.prefix(3).enumerated().reversed()), id: \.element.id) { index, photo in
                    FilmThumb(photo: photo, flag: .none, current: false, previews: flow.session.previews, width: 66, height: 44)
                        .shadow(color: .black.opacity(0.4), radius: 6, y: 3)
                        .rotationEffect(.degrees(Double(index) * -6))
                        .offset(x: CGFloat(index) * -6, y: CGFloat(index) * -3)
                }
            }
            .frame(width: 84, height: 60)

            VStack(alignment: .leading, spacing: 3) {
                Text("Import \(Format.plural(flow.photos.count, "pick"))")
                    .font(.system(size: 18, weight: .semibold))
                Text("From \(flow.session.cameraName) · \(Format.plural(flow.fileCount, "file")) (\(Format.bytes(flow.byteCount)))")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .monospacedDigit()
            }
        }
    }

    private func layoutRow(_ layout: FolderLayout) -> some View {
        let selected = flow.options.layout == layout
        let title = switch layout {
        case .byDate: "By date"
        case .keepCardFolders: "Keep card folders"
        case .singleFolder: "All in one folder"
        }
        return Button {
            flow.options.layout = layout
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Theme.pick)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                Text(flow.example(for: layout))
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: 36)
            .background(selected ? Color.white.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct SheetSection<Content: View>: View {
    let title: String
    let content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
            content
        }
    }
}
