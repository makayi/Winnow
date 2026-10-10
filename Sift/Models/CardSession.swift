import Foundation
import Observation

enum PhotoFilter: Hashable, CaseIterable {
    case all, picks, rejects, unflagged, notImported

    var title: String {
        switch self {
        case .all: "All photos"
        case .picks: "Picks"
        case .rejects: "Rejects"
        case .unflagged: "Not flagged"
        case .notImported: "Not yet imported"
        }
    }

    var symbol: String {
        switch self {
        case .all: "photo.on.rectangle"
        case .picks: "flag.fill"
        case .rejects: "xmark"
        case .unflagged: "circle.dashed"
        case .notImported: "square.and.arrow.down"
        }
    }
}

/// Everything about the card (or folder) being browsed.
@MainActor @Observable
final class CardSession {
    let source: SourceInfo
    @ObservationIgnored let store: CardStore
    @ObservationIgnored let previews: PreviewLoader

    private(set) var photos: [Photo] = []
    private(set) var visible: [Photo] = []
    private(set) var isScanning = true
    var scanError: String?
    private(set) var exif: [String: Exif] = [:]
    private(set) var flags: [String: Flag] = [:]
    private(set) var importRecords: [String: [ImportRecord]] = [:]
    var isEjected = false

    var filter: PhotoFilter = .all { didSet { refreshVisible() } }
    var folderFilter: String? { didSet { refreshVisible() } }
    var selectedID: String?

    @ObservationIgnored private var exifTask: Task<Void, Never>?

    init(source: SourceInfo, store: CardStore, previews: PreviewLoader) {
        self.source = source
        self.store = store
        self.previews = previews
        let state = store.load(cardID: source.cardID)
        flags = state.flags
        importRecords = Dictionary(grouping: state.imports, by: \.photoID)
    }

    // MARK: Scanning

    func scan() async {
        isScanning = true
        let root = source.rootURL
        do {
            let found = try await Task.detached(priority: .userInitiated) { try CardScanner.scan(root: root) }.value
            photos = found
            refreshVisible()
            if selectedID == nil { selectedID = visible.first?.id }
            scanError = nil
        } catch {
            scanError = error.localizedDescription
        }
        isScanning = false
        loadExif()
    }

    /// Reads EXIF lazily in the background, two at a time, flushing updates in batches.
    private func loadExif() {
        exifTask?.cancel()
        let pending = photos.filter { exif[$0.id] == nil }
        exifTask = Task { [weak self] in
            var batch: [String: Exif] = [:]
            var lastFlush = Date()
            await withTaskGroup(of: (String, Exif).self) { group in
                var iterator = pending.makeIterator()
                for _ in 0..<2 {
                    if let p = iterator.next() { group.addTask(priority: .utility) { (p.id, ExifReader.read(p)) } }
                }
                for await (id, value) in group {
                    if Task.isCancelled { group.cancelAll(); return }
                    batch[id] = value
                    if Date().timeIntervalSince(lastFlush) > 0.3 {
                        self?.mergeExif(batch)
                        batch.removeAll()
                        lastFlush = Date()
                    }
                    if let p = iterator.next() { group.addTask(priority: .utility) { (p.id, ExifReader.read(p)) } }
                }
            }
            self?.mergeExif(batch)
        }
    }

    private func mergeExif(_ batch: [String: Exif]) {
        guard !batch.isEmpty else { return }
        exif.merge(batch) { _, new in new }
    }

    /// Loads EXIF for one photo right away (the loupe shouldn't wait for the background pass).
    func ensureExif(for photo: Photo) async {
        guard exif[photo.id] == nil else { return }
        let value = await Task.detached(priority: .userInitiated) { ExifReader.read(photo) }.value
        exif[photo.id] = value
    }

    // MARK: Derived

    var cameraName: String {
        if let first = photos.first, let camera = exif[first.id]?.camera { return camera.uppercased() }
        return source.name
    }

    var folders: [(name: String, count: Int)] {
        var counts: [String: Int] = [:]
        for p in photos { counts[p.folder, default: 0] += 1 }
        return counts.sorted { $0.key < $1.key }.map { ($0.key, $0.value) }
    }

    func flag(_ id: String) -> Flag { flags[id] ?? .none }

    func isImported(_ photo: Photo) -> Bool {
        guard let records = importRecords[photo.id] else { return false }
        let current = Dictionary(uniqueKeysWithValues: [(photo.raf, photo.rafSize), (photo.jpg, photo.jpgSize)]
            .compactMap { url, size in url.map { ($0.lastPathComponent.lowercased(), size) } })
        return records.contains { current[$0.fileName.lowercased()] == $0.size }
    }

    func matches(_ photo: Photo, _ filter: PhotoFilter) -> Bool {
        switch filter {
        case .all: true
        case .picks: flag(photo.id) == .pick
        case .rejects: flag(photo.id) == .reject
        case .unflagged: flag(photo.id) == .none
        case .notImported: !isImported(photo)
        }
    }

    func count(_ filter: PhotoFilter) -> Int {
        photos.lazy.filter { (self.folderFilter == nil || $0.folder == self.folderFilter) && self.matches($0, filter) }.count
    }

    var picks: [Photo] { photos.filter { flag($0.id) == .pick } }
    var rejects: [Photo] { photos.filter { flag($0.id) == .reject } }

    var selected: Photo? {
        guard let selectedID else { return nil }
        return visible.first { $0.id == selectedID } ?? photos.first { $0.id == selectedID }
    }

    var selectedIndex: Int? { selectedID.flatMap { id in visible.firstIndex { $0.id == id } } }

    private func refreshVisible() {
        visible = photos.filter { (folderFilter == nil || $0.folder == folderFilter) && matches($0, filter) }
    }

    // MARK: Culling

    func setFlag(_ flag: Flag, for id: String) {
        flags[id] = flag == .none ? nil : flag
        // In a filtered view the photo may drop out; move the selection to its neighbour.
        if filter != .all && filter != .notImported {
            let keep = visible.contains { $0.id == id }
            refreshVisible()
            if keep, !visible.contains(where: { $0.id == id }) {
                selectNearest(after: id)
            }
        }
        persist()
    }

    private func selectNearest(after id: String) {
        guard let all = photos.firstIndex(where: { $0.id == id }) else { return }
        let next = photos[all...].dropFirst().first { visible.contains($0) } ?? photos[..<all].last { visible.contains($0) }
        selectedID = next?.id
    }

    func moveSelection(by delta: Int) {
        guard !visible.isEmpty else { return }
        let current = selectedIndex ?? (delta > 0 ? -1 : visible.count)
        let next = min(max(current + delta, 0), visible.count - 1)
        selectedID = visible[next].id
    }

    // MARK: Imports

    func recordImport(_ result: PhotoResult) {
        let records = result.verified.map {
            ImportRecord(photoID: result.photo.id, basename: result.photo.basename, fileName: $0.source.lastPathComponent,
                         size: $0.size, sha256: $0.sha256, destinationPath: $0.destination.path, date: Date())
        }
        var existing = importRecords[result.photo.id] ?? []
        existing.removeAll { r in records.contains { $0.fileName == r.fileName } }
        importRecords[result.photo.id] = existing + records
        if filter == .notImported { refreshVisible() }
        persist()
    }

    /// Drops deleted files from the model. A photo with nothing left on the card disappears.
    func applyDeletion(_ deleted: [URL]) {
        let gone = Set(deleted.map(\.standardizedFileURL))
        photos = photos.compactMap { p in
            var p = p
            if let raf = p.raf, gone.contains(raf.standardizedFileURL) { p.raf = nil; p.rafSize = 0 }
            if let jpg = p.jpg, gone.contains(jpg.standardizedFileURL) { p.jpg = nil; p.jpgSize = 0 }
            return p.isEmpty ? nil : p
        }
        refreshVisible()
        if let id = selectedID, !visible.contains(where: { $0.id == id }) { selectedID = visible.first?.id }
    }

    private func persist() {
        let state = CardState(cardID: source.cardID, flags: flags, imports: importRecords.values.flatMap { $0 })
        store.saveInBackground(state)
    }
}
