import SwiftUI

/// Hosts the import flow in a system sheet (Liquid Glass comes with it).
struct ImportSheetContainer: View {
    let flow: ImportFlow

    var body: some View {
        Group {
            if flow.phase == .options {
                ImportSheet(flow: flow)
            } else {
                ImportProgressView(flow: flow)
                    .padding(24)
            }
        }
        .frame(width: 580)
        .interactiveDismissDisabled(flow.phase == .copying || flow.phase == .asking)
    }
}

struct ImportSheet: View {
    @Bindable var flow: ImportFlow

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 4)

            Form {
                Section("Destination") {
                    HStack(spacing: 10) {
                        Image(systemName: "folder")
                            .foregroundStyle(.secondary)
                        Text(Format.abbreviatedPath(flow.options.destinationPath))
                            .font(Theme.mono)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button("Choose…") { flow.chooseDestination() }
                    }
                }

                Section("Folders") {
                    ForEach(FolderLayout.allCases, id: \.self) { layout in
                        layoutRow(layout)
                    }
                }

                Section("Files") {
                    Picker("Files", selection: $flow.options.fileTypes) {
                        ForEach(FileTypeChoice.allCases, id: \.self) { Text($0.label).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }

                Section {
                    Toggle(isOn: .constant(true)) {
                        Text("Verify every copy")
                        Text("Each file is checked against the card before it's kept.")
                    }
                    .disabled(true)
                    Toggle("Mark as imported", isOn: $flow.options.markImported)
                    if flow.lightroomInstalled {
                        Toggle("Open folder in Lightroom", isOn: $flow.options.openInLightroom)
                    }
                    if flow.session.source.isCard {
                        Toggle("Eject card when done", isOn: $flow.options.ejectWhenDone)
                    }
                } header: {
                    Text("After copying")
                } footer: {
                    if let preview = flow.firstFilePreview {
                        Text("First file will be saved as \(Text(preview).font(Theme.mono))")
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: 470)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { flow.close() }
                    .keyboardShortcut(.cancelAction)
                Button("Import \(Format.plural(flow.photos.count, "photo"))") { flow.start() }
                    .buttonStyle(.glassProminent)
                    .tint(Theme.pick)
                    .foregroundStyle(Theme.onPick)
                    .keyboardShortcut(.defaultAction)
            }
            .controlSize(.large)
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
            .padding(.top, 4)
        }
    }

    private var header: some View {
        HStack(spacing: 18) {
            ZStack {
                ForEach(Array(flow.photos.prefix(3).enumerated().reversed()), id: \.element.id) { index, photo in
                    FilmThumb(photo: photo, flag: .none, current: false, previews: flow.session.previews, width: 66, height: 44)
                        .shadow(color: .black.opacity(0.25), radius: 5, y: 2)
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
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
            Spacer(minLength: 0)
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
                    .foregroundStyle(.tint)
                    .opacity(selected ? 1 : 0)
                    .frame(width: 16)
                Text(title)
                Spacer()
                Text(flow.example(for: layout))
                    .font(Theme.mono)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
