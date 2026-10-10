import AppKit
import Observation

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
    var gridColumns = 1
    var ejectError: String?
    /// The last folder opened with File > Open Folder, so it stays in the source picker.
    private(set) var openedFolder: SourceInfo?

    var thumbnailSize: CGFloat {
        didSet { UserDefaults.standard.set(Double(thumbnailSize), forKey: "thumbnailSize") }
    }

    init() {
        let saved = UserDefaults.standard.double(forKey: "thumbnailSize")
        thumbnailSize = saved > 0 ? min(max(saved, Theme.minThumb), Theme.maxThumb) : 240
        watcher.onMount = { [weak self] card in self?.cardMounted(card) }
        watcher.onUnmount = { [weak self] url in self?.volumeUnmounted(url) }
        watcher.start()
        let args = UserDefaults.standard
        if let path = args.string(forKey: "open") {
            // `Sift -open /path/to/folder` opens a folder at launch.
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
        mode = .grid
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
        mode = .grid
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
                ejectError = "Sift couldn't eject \(session.source.name). \(error.localizedDescription)"
            }
        }
    }

    // MARK: Thumbnails

    func biggerThumbnails() { thumbnailSize = min(Theme.maxThumb, thumbnailSize + Theme.thumbStep) }
    func smallerThumbnails() { thumbnailSize = max(Theme.minThumb, thumbnailSize - Theme.thumbStep) }

    // MARK: Loupe

    func openLoupe() {
        guard let session, session.selected != nil else { return }
        zoomed = false
        mode = .loupe
    }

    func closeLoupe() {
        zoomed = false
        mode = .grid
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
