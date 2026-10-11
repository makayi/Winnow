import AppKit
import Observation
import SwiftUI

enum ViewMode { case grid, loupe }

@MainActor @Observable
final class AppModel {
    let watcher = VolumeWatcher()
    @ObservationIgnored let store = CardStore()
    @ObservationIgnored let previews = PreviewLoader()

    var session: CardSession?
    var mode: ViewMode = .grid
    var zoomed = false
    var importFlow: ImportFlow?
    var columnVisibility: NavigationSplitViewVisibility = .all
    /// Whether the loupe's info inspector is showing. Only ever true in the loupe.
    var inspectorPresented = false
    /// The user's choice for the inspector, remembered between visits to the loupe.
    @ObservationIgnored private var wantsInspector = true
    @ObservationIgnored private var visibilityBeforeLoupe: NavigationSplitViewVisibility = .all
    var gridColumns = 1
    var ejectError: String?
    /// The last folder opened with File > Open Folder, so it stays in the source picker.
    private(set) var openedFolder: SourceInfo?

    var thumbnailSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(thumbnailSize), forKey: "thumbnailSize") }
    }

    init() {
        LegacyMigration.run()
        let saved = UserDefaults.standard.double(forKey: "thumbnailSize")
        thumbnailSize = saved > 0 ? min(max(saved, Theme.minThumb), Theme.maxThumb) : 240
        watcher.onMount = { [weak self] card in self?.cardMounted(card) }
        watcher.onUnmount = { [weak self] url in self?.volumeUnmounted(url) }
        watcher.start()
        let args = UserDefaults.standard
        if let path = args.string(forKey: "open") {
            // `Winnow -open /path/to/folder` opens a folder at launch.
            open(VolumeWatcher.sourceInfo(forFolder: URL(fileURLWithPath: path, isDirectory: true)))
        } else if let card = watcher.cards.first {
            open(card)
        }
    }

    var sources: [SourceInfo] {
        watcher.cards + (openedFolder.map { [$0] } ?? [])
    }

    func open(_ source: SourceInfo) {
        if session?.source == source && session?.isEjected == false { return }
        if source.kind == .folder { openedFolder = source }
        if mode == .loupe { closeLoupe() }
        zoomed = false
        let session = CardSession(source: source, store: store, previews: previews)
        self.session = session
        Task { await session.scan() }
    }

    func openFolderPanel() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Open"
        panel.message = "Choose a folder of photos to browse"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        open(VolumeWatcher.sourceInfo(forFolder: url))
    }

    private func cardMounted(_ card: SourceInfo) {
        NSApp.activate()
        NSApp.windows.first { $0.isVisible }?.makeKeyAndOrderFront(nil)
        // Never switch away in the middle of an import.
        guard importFlow == nil else { return }
        open(card)
    }

    private func volumeUnmounted(_ url: URL) {
        guard let session, session.source.isCard,
              session.source.rootURL.standardizedFileURL == url.standardizedFileURL else { return }
        session.isEjected = true
        if importFlow == nil { leaveEjectedSession() }
    }

    func leaveEjectedSession() {
        guard session?.isEjected == true else { return }
        session = nil
        if mode == .loupe { closeLoupe() }
        if let next = sources.first { open(next) }
    }

    var canEject: Bool { session?.source.isCard == true && session?.isEjected == false }

    func ejectCurrent() {
        guard let session, session.source.isCard, !session.isEjected else { return }
        let url = session.source.rootURL
        Task {
            do {
                try await VolumeWatcher.eject(url)
            } catch {
                ejectError = "Winnow couldn't eject \(session.source.name). \(error.localizedDescription)"
            }
        }
    }

    // MARK: Thumbnails

    func biggerThumbnails() { thumbnailSize = min(Theme.maxThumb, thumbnailSize + Theme.thumbStep) }
    func smallerThumbnails() { thumbnailSize = max(Theme.minThumb, thumbnailSize - Theme.thumbStep) }

    // MARK: Loupe

    func openLoupe() {
        guard let session, session.selected != nil, mode != .loupe else { return }
        zoomed = false
        mode = .loupe
        // The photo gets the whole window; the sidebar comes back with the grid.
        visibilityBeforeLoupe = columnVisibility
        columnVisibility = .detailOnly
        inspectorPresented = wantsInspector
    }

    func toggleInspector() {
        inspectorPresented.toggle()
        wantsInspector = inspectorPresented
    }

    func closeLoupe() {
        guard mode == .loupe else { return }
        zoomed = false
        inspectorPresented = false
        mode = .grid
        // Closing the inspector and showing the sidebar in the same update leaves the detail column
        // laid out at its old width (grid and toolbar run off the right edge). Show the sidebar once
        // the inspector has gone.
        let restore = visibilityBeforeLoupe
        DispatchQueue.main.async { [weak self] in
            guard let self, self.mode == .grid else { return }
            withAnimation(.easeInOut(duration: 0.25)) { self.columnVisibility = restore }
        }
    }

    // MARK: Import

    var canImport: Bool { session.map { !$0.picks.isEmpty && !$0.isEjected } ?? false && importFlow == nil }

    func openImport() {
        guard canImport, let session else { return }
        importFlow = ImportFlow(session: session, app: self)
    }

    func closeImport() {
        importFlow = nil
        leaveEjectedSession()
    }
}
