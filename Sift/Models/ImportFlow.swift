import AppKit
import Observation

/// Drives the import sheet: options → copying → delete prompt → finished.
@MainActor @Observable
final class ImportFlow {
    enum Phase { case options, copying, asking, finished }

    let session: CardSession
    @ObservationIgnored private weak var app: AppModel?
    let photos: [Photo]

    var phase: Phase = .options
    var options: ImportOptions { didSet { options.save() } }
    var progress = ImportProgress()
    var result: ImportResult?
    var stopping = false
    var alsoDeleteRejects = false
    var isDeleting = false
    var deletedCount = 0
    var deleteFailures: [URL] = []
    var didDelete = false
    @ObservationIgnored private let stopSignal = StopSignal()

    init(session: CardSession, app: AppModel) {
        self.session = session
        self.app = app
        self.photos = session.picks
        self.options = ImportOptions.load()
    }

    // MARK: Summary

    var fileCount: Int { photos.reduce(0) { $0 + Importer.files(for: $1, choice: options.fileTypes).count } }
    var byteCount: Int64 { photos.reduce(0) { $0 + Importer.byteCount(for: $1, choice: options.fileTypes) } }
    var lightroomInstalled: Bool { Lightroom.appURL != nil }

    var firstFilePreview: String? {
        guard let first = photos.first, let file = Importer.files(for: first, choice: options.fileTypes).first else { return nil }
        let date = session.exif[first.id]?.dateTaken ?? first.fileDate
        let dir = Importer.directory(for: ImportItem(photo: first, captureDate: date), options: options)
        return Format.abbreviatedPath(dir.appendingPathComponent(file.lastPathComponent).path)
    }

    func example(for layout: FolderLayout) -> String {
        let date = photos.first.flatMap { session.exif[$0.id]?.dateTaken ?? $0.fileDate } ?? Date()
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        switch layout {
        case .byDate: return String(format: "%04d/%04d-%02d-%02d", c.year ?? 0, c.year ?? 0, c.month ?? 0, c.day ?? 0)
        case .keepCardFolders: return photos.first?.folder ?? "100_FUJI"
        case .singleFolder: return "Everything in \(options.destination.lastPathComponent)"
        }
    }

    var rejectsOnCard: [Photo] { session.rejects }

    // MARK: Actions

    func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.prompt = "Choose"
        panel.directoryURL = options.destination
        if panel.runModal() == .OK, let url = panel.url { options.destinationPath = url.path }
    }

    func start() {
        guard phase == .options, !photos.isEmpty else { return }
        phase = .copying
        progress = ImportProgress(totalFiles: fileCount, bytesTotal: byteCount)
        let photos = self.photos
        let knownExif = session.exif
        let options = self.options
        let stop = stopSignal
        let session = self.session

        Task {
            let result = await Task.detached(priority: .userInitiated) { () -> ImportResult in
                let items = photos.map { p in
                    ImportItem(photo: p, captureDate: knownExif[p.id]?.dateTaken ?? ExifReader.read(p).dateTaken ?? p.fileDate)
                }
                let result = Importer().run(
                    items: items, options: options, stop: stop,
                    progress: { p in DispatchQueue.main.async { self.progress = p } },
                    photoFinished: { r in
                        guard options.markImported else { return }
                        DispatchQueue.main.async { session.recordImport(r) }
                    })
                Importer.removePartials(in: items.map { Importer.directory(for: $0, options: options) })
                return result
            }.value
            // Let queued progress updates land first.
            await withCheckedContinuation { c in DispatchQueue.main.async { c.resume() } }
            finishCopying(result)
        }
    }

    private func finishCopying(_ result: ImportResult) {
        self.result = result
        if options.openInLightroom, !result.verified.isEmpty {
            let dirs = Set(result.verified.flatMap { $0.verified.map { $0.destination.deletingLastPathComponent() } })
            Lightroom.open(Array(dirs).sorted { $0.path < $1.path }.first ?? options.destination)
        }
        let cardPresent = FileManager.default.fileExists(atPath: session.source.rootURL.appendingPathComponent("DCIM").path)
        if session.source.isCard, !session.isEjected, cardPresent, !result.verified.isEmpty {
            phase = .asking
        } else {
            finish()
        }
    }

    func stop() {
        stopping = true
        stopSignal.stop()
    }

    func keepOnCard() { finish() }

    func deleteFromCard() {
        guard let result, !isDeleting else { return }
        isDeleting = true
        let rejects = alsoDeleteRejects ? rejectsOnCard : []
        let plan = Importer.deletionPlan(result: result, rejects: rejects)
        let verified = result.verified.flatMap(\.verified)
        let photoCount = result.verified.count + rejects.count
        Task {
            let outcome = await Task.detached { Importer.delete(plan, verified: verified) }.value
            session.applyDeletion(outcome.deleted)
            deleteFailures = outcome.failed
            deletedCount = photoCount
            didDelete = true
            isDeleting = false
            finish()
        }
    }

    private func finish() {
        phase = .finished
        if options.ejectWhenDone, session.source.isCard, !session.isEjected { app?.ejectCurrent() }
    }

    var destinationFolders: [URL] {
        guard let result else { return [] }
        return Array(Set(result.verified.flatMap { $0.verified.map { $0.destination.deletingLastPathComponent() } }))
            .sorted { $0.path < $1.path }
    }

    func showInFinder() {
        let files = result?.verified.flatMap { $0.verified.map(\.destination) } ?? []
        if files.isEmpty {
            NSWorkspace.shared.open(options.destination)
        } else {
            NSWorkspace.shared.activateFileViewerSelecting(files)
        }
    }

    func close() { app?.closeImport() }
}
