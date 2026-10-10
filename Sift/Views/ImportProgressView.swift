import SwiftUI

/// Copying → delete prompt → finished, in one view.
struct ImportProgressView: View {
    @Environment(AppModel.self) private var app
    @Bindable var flow: ImportFlow

    var body: some View {
        switch flow.phase {
        case .options: EmptyView()
        case .copying: copying
        case .asking: asking
        case .finished: finished
        }
    }

    // MARK: Copying

    private var copying: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Importing \(Format.plural(flow.photos.count, "photo"))")
                .font(.system(size: 18, weight: .semibold))
            ProgressView(value: flow.progress.fraction)
                .progressViewStyle(.linear)
                .tint(Theme.pick)
            HStack {
                Text("\(flow.progress.completedFiles) of \(flow.progress.totalFiles) files")
                    .monospacedDigit()
                Spacer()
                Text(flow.progress.currentFile)
                    .font(Theme.mono)
                    .foregroundStyle(Theme.textSecondary)
            }
            .font(.system(size: 13))
            Text(flow.stopping
                 ? "Stopping after this file. Finished copies stay where they are."
                 : "Every copy is checked against the card before it's kept.")
                .font(.system(size: 12))
                .foregroundStyle(Theme.textSecondary)
            HStack {
                Spacer()
                Button(flow.stopping ? "Stopping…" : "Stop") { flow.stop() }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .disabled(flow.stopping)
            }
        }
    }

    // MARK: Delete prompt

    private var asking: some View {
        let result = flow.result ?? ImportResult()
        let verified = result.verified
        let rejects = flow.rejectsOnCard.count
        return VStack(alignment: .leading, spacing: 18) {
            successHeader(
                title: "\(Format.plural(verified.count, "photo")) imported",
                detail: "All \(result.verifiedFileCount) files copied and checked against the card")

            FailureList(result: result)

            VStack(alignment: .leading, spacing: 10) {
                Text("Delete \(verified.count == 1 ? "this photo" : "these \(verified.count) photos") from the card?")
                    .font(.system(size: 15, weight: .semibold))
                Text("\(Text("Your copies are in ").foregroundStyle(Theme.textSecondary))\(Text(Format.abbreviatedPath(destinationPath)).font(Theme.mono))")
                    .font(.system(size: 12.5))
                    .lineLimit(2)
                    .truncationMode(.middle)
                Text("Everything else on the card stays where it is. This can't be undone.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                if rejects > 0 {
                    Toggle("Also delete the \(Format.plural(rejects, "photo")) I rejected", isOn: $flow.alsoDeleteRejects)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 13))
                        .padding(.top, 2)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white.opacity(0.06), in: RoundedRectangle(cornerRadius: 16, style: .continuous))

            HStack(spacing: 10) {
                Spacer()
                Button("Keep on card") { flow.keepOnCard() }
                    .buttonStyle(.glass)
                    .keyboardShortcut(.defaultAction)
                Button(role: .destructive) {
                    flow.deleteFromCard()
                } label: {
                    Label(flow.isDeleting ? "Deleting…" : "Delete from card", systemImage: "trash")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.reject)
                .foregroundStyle(Theme.onPick)
                .disabled(flow.isDeleting)
            }
            .controlSize(.extraLarge)
        }
    }

    // MARK: Finished

    private var finished: some View {
        let result = flow.result ?? ImportResult()
        let verified = result.verified.count
        let title: String
        let detail: String
        if flow.didDelete {
            title = "Deleted from the card"
            detail = "\(Format.plural(flow.session.photos.count, "photo")) still on the card"
        } else if verified == 0 {
            title = result.stopped ? "Import stopped" : "Nothing was imported"
            detail = "Your photos are still on the card."
        } else {
            title = "All done"
            detail = "\(Format.plural(verified, "photo")) imported to \(Format.abbreviatedPath(destinationPath))"
        }

        return VStack(alignment: .leading, spacing: 18) {
            if verified > 0 {
                successHeader(title: title, detail: detail)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 18, weight: .semibold))
                    Text(detail).font(.system(size: 13)).foregroundStyle(Theme.textSecondary)
                }
            }

            if result.stopped, result.skippedCount > 0 {
                Text("Stopped before \(Format.plural(result.skippedCount, "photo")) were copied. Nothing half-copied was left behind.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
            }

            FailureList(result: result)

            if !flow.deleteFailures.isEmpty {
                Label("\(Format.plural(flow.deleteFailures.count, "file")) couldn't be deleted and are still on the card.",
                      systemImage: "xmark")
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.reject)
            }

            HStack(spacing: 10) {
                if verified > 0 {
                    Button("Show in Finder") { flow.showInFinder() }
                        .buttonStyle(.glass)
                }
                if app.canEject {
                    Button { app.ejectCurrent() } label: { Label("Eject card", systemImage: "eject") }
                        .buttonStyle(.glass)
                }
                Spacer()
                Button {
                    flow.close()
                } label: {
                    Text(flow.session.isEjected ? "Done" : "Back to card").fontWeight(.semibold)
                }
                .buttonStyle(.glassProminent)
                .tint(Theme.pick)
                .foregroundStyle(Theme.onPick)
                .keyboardShortcut(.defaultAction)
            }
            .controlSize(.extraLarge)
        }
    }

    // MARK: Helpers

    private var destinationPath: String {
        let folders = flow.destinationFolders
        return folders.count == 1 ? folders[0].path : flow.options.destinationPath
    }

    private func successHeader(title: String, detail: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: "checkmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(Theme.onPick)
                .frame(width: 38, height: 38)
                .background(Theme.success, in: .circle)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.system(size: 18, weight: .semibold))
                Text(detail)
                    .font(.system(size: 12.5))
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(2)
            }
        }
    }
}

private struct FailureList: View {
    let result: ImportResult

    var body: some View {
        let failed = result.failed
        if !failed.isEmpty {
            VStack(alignment: .leading, spacing: 6) {
                Text("\(Format.plural(failed.count, "photo")) couldn't be imported and stay on the card:")
                    .font(.system(size: 13, weight: .semibold))
                ForEach(failed.prefix(5), id: \.photo.id) { r in
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "xmark")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(Theme.reject)
                        Text(r.photo.basename).font(Theme.mono)
                        Text(r.failure ?? "")
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.textSecondary)
                            .lineLimit(1)
                    }
                }
                if failed.count > 5 {
                    Text("and \(failed.count - 5) more")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.reject.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
    }
}
