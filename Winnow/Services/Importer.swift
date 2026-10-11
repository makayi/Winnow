import AppKit
import CryptoKit
import Foundation

enum FolderLayout: String, Codable, CaseIterable, Sendable {
    case byDate, keepCardFolders, singleFolder
}

enum FileTypeChoice: String, Codable, CaseIterable, Sendable {
    case both, rafOnly, jpgOnly

    var label: String {
        switch self {
        case .both: "RAF + JPG"
        case .rafOnly: "RAF only"
        case .jpgOnly: "JPG only"
        }
    }
}

struct ImportOptions: Codable, Equatable, Sendable {
    var destinationPath = ("~/Pictures/Fuji" as NSString).expandingTildeInPath
    var layout: FolderLayout = .byDate
    var fileTypes: FileTypeChoice = .both
    var markImported = true
    var openInLightroom = false
    var ejectWhenDone = false

    var destination: URL { URL(fileURLWithPath: destinationPath, isDirectory: true) }

    private static let defaultsKey = "importOptions"

    static func load(_ defaults: UserDefaults = .standard) -> ImportOptions {
        guard let data = defaults.data(forKey: defaultsKey),
              let options = try? JSONDecoder().decode(ImportOptions.self, from: data) else { return ImportOptions() }
        return options
    }

    func save(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) { defaults.set(data, forKey: Self.defaultsKey) }
    }
}

struct ImportItem: Sendable {
    let photo: Photo
    /// EXIF DateTimeOriginal, or the file date when EXIF is unreadable.
    let captureDate: Date
}

struct VerifiedFile: Sendable, Hashable {
    enum Outcome: Sendable { case copied, alreadyImported }
    let source: URL
    let destination: URL
    let sha256: String
    let size: Int64
    let outcome: Outcome
}

struct PhotoResult: Sendable {
    let photo: Photo
    var expectedFiles: [URL]
    var verified: [VerifiedFile] = []
    var failure: String?

    /// Every selected file of this photo was copied and its hash matched the card.
    var isVerified: Bool { failure == nil && !expectedFiles.isEmpty && verified.count == expectedFiles.count }
}

struct ImportResult: Sendable {
    var photos: [PhotoResult] = []
    var stopped = false

    var verified: [PhotoResult] { photos.filter(\.isVerified) }
    var failed: [PhotoResult] { photos.filter { $0.failure != nil } }
    var verifiedFileCount: Int { verified.reduce(0) { $0 + $1.verified.count } }
    var skippedCount: Int { photos.count - verified.count - failed.count }
}

struct ImportProgress: Sendable, Equatable {
    var completedFiles = 0
    var totalFiles = 0
    var bytesDone: Int64 = 0
    var bytesTotal: Int64 = 0
    var currentFile = ""

    var fraction: Double { bytesTotal > 0 ? Double(bytesDone) / Double(bytesTotal) : 0 }
}

/// Thread-safe stop button state. Stop takes effect after the current file.
final class StopSignal: @unchecked Sendable {
    private let lock = NSLock()
    private var stopped = false
    var isStopped: Bool { lock.withLock { stopped } }
    func stop() { lock.withLock { stopped = true } }
}

enum ImportError: LocalizedError {
    case hashMismatch(String)
    case io(String, Int32)
    case sourceChanged(String)

    var errorDescription: String? {
        switch self {
        case .hashMismatch(let name): "\(name): the copy didn't match the card"
        case .io(let name, let code): "\(name): \(String(cString: strerror(code)))"
        case .sourceChanged(let name): "\(name) changed on the card"
        }
    }
}

struct Importer: Sendable {
    var chunkSize = 4 << 20
    /// Test hook: runs on the partial copy before it is verified (used to corrupt it on purpose).
    var afterCopy: (@Sendable (URL) throws -> Void)?

    init(afterCopy: (@Sendable (URL) throws -> Void)? = nil) {
        self.afterCopy = afterCopy
    }

    // MARK: Planning

    /// Files to copy for a photo. If the photo lacks the chosen type, fall back to what it has,
    /// so a pick is never silently left behind.
    static func files(for photo: Photo, choice: FileTypeChoice) -> [URL] {
        switch choice {
        case .both: photo.files
        case .rafOnly: photo.raf.map { [$0] } ?? photo.files
        case .jpgOnly: photo.jpg.map { [$0] } ?? photo.files
        }
    }

    static func byteCount(for photo: Photo, choice: FileTypeChoice) -> Int64 {
        files(for: photo, choice: choice).reduce(0) { $0 + ($1 == photo.raf ? photo.rafSize : photo.jpgSize) }
    }

    static func directory(for item: ImportItem, options: ImportOptions) -> URL {
        switch options.layout {
        case .singleFolder:
            return options.destination
        case .keepCardFolders:
            return options.destination.appendingPathComponent(item.photo.folder, isDirectory: true)
        case .byDate:
            let c = Calendar.current.dateComponents([.year, .month, .day], from: item.captureDate)
            let year = String(format: "%04d", c.year ?? 0)
            let day = String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
            return options.destination.appendingPathComponent(year, isDirectory: true)
                .appendingPathComponent(day, isDirectory: true)
        }
    }

    // MARK: Running

    /// Copies, verifies and renames every file. Synchronous; call it off the main thread.
    func run(
        items: [ImportItem],
        options: ImportOptions,
        stop: StopSignal = StopSignal(),
        progress: @Sendable (ImportProgress) -> Void = { _ in },
        photoFinished: @Sendable (PhotoResult) -> Void = { _ in }
    ) -> ImportResult {
        let plan = items.map { (item: $0, files: Self.files(for: $0.photo, choice: options.fileTypes)) }
        var p = ImportProgress()
        p.totalFiles = plan.reduce(0) { $0 + $1.files.count }
        p.bytesTotal = plan.reduce(0) { $0 + Self.byteCount(for: $1.item.photo, choice: options.fileTypes) }
        progress(p)

        var result = ImportResult()
        for (item, files) in plan {
            var photoResult = PhotoResult(photo: item.photo, expectedFiles: files)
            if stop.isStopped {
                result.stopped = true
                result.photos.append(photoResult)
                continue
            }
            let dir = Self.directory(for: item, options: options)
            for file in files {
                if stop.isStopped { result.stopped = true; break }
                p.currentFile = file.lastPathComponent
                progress(p)
                do {
                    photoResult.verified.append(try importFile(file, into: dir))
                } catch {
                    photoResult.failure = error.localizedDescription
                }
                p.completedFiles += 1
                p.bytesDone += file == item.photo.raf ? item.photo.rafSize : item.photo.jpgSize
                progress(p)
                if photoResult.failure != nil { break }
            }
            if photoResult.isVerified { photoFinished(photoResult) }
            result.photos.append(photoResult)
        }
        if stop.isStopped { result.stopped = true }
        p.currentFile = ""
        progress(p)
        return result
    }

    /// Copy to a hidden partial, check SHA-256 against the card, then rename into place.
    func importFile(_ source: URL, into dir: URL) throws -> VerifiedFile {
        let fm = FileManager.default
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let name = source.lastPathComponent
        let attrs = try fm.attributesOfItem(atPath: source.path)
        let size = (attrs[.size] as? NSNumber)?.int64Value ?? 0

        // Name clash: same content means it's already imported; otherwise suffix -1, -2…
        var sourceHash: String?
        var target = dir.appendingPathComponent(name)
        var n = 0
        while fm.fileExists(atPath: target.path) {
            let existing = (try? fm.attributesOfItem(atPath: target.path)[.size] as? NSNumber)?.int64Value
            if existing == size {
                if sourceHash == nil { sourceHash = try FileIO.sha256(of: source, chunkSize: chunkSize) }
                if try FileIO.sha256(of: target, chunkSize: chunkSize) == sourceHash {
                    return VerifiedFile(source: source, destination: target, sha256: sourceHash!, size: size,
                                        outcome: .alreadyImported)
                }
            }
            n += 1
            let stem = source.deletingPathExtension().lastPathComponent
            target = dir.appendingPathComponent("\(stem)-\(n)").appendingPathExtension(source.pathExtension)
        }

        let partial = dir.appendingPathComponent(".\(target.lastPathComponent).winnow-partial")
        var lastError: Error = ImportError.hashMismatch(name)
        for _ in 0..<2 {  // one retry
            do {
                defer { try? fm.removeItem(at: partial) }
                let copiedHash = try FileIO.copy(from: source, to: partial, chunkSize: chunkSize)
                try afterCopy?(partial)
                let partialHash = try FileIO.sha256(of: partial, chunkSize: chunkSize)
                guard copiedHash == partialHash else { throw ImportError.hashMismatch(name) }
                if let sourceHash, sourceHash != copiedHash { throw ImportError.sourceChanged(name) }
                // Atomic rename; moveItem refuses to overwrite.
                try fm.moveItem(at: partial, to: target)
                var dates: [FileAttributeKey: Any] = [:]
                if let c = attrs[.creationDate] { dates[.creationDate] = c }
                if let m = attrs[.modificationDate] { dates[.modificationDate] = m }
                try? fm.setAttributes(dates, ofItemAtPath: target.path)
                return VerifiedFile(source: source, destination: target, sha256: copiedHash, size: size,
                                    outcome: .copied)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    /// Removes leftover partials, e.g. after a card was pulled mid-copy.
    static func removePartials(in dirs: [URL]) {
        let fm = FileManager.default
        for dir in Set(dirs) {
            guard let names = try? fm.contentsOfDirectory(atPath: dir.path) else { continue }
            // ".sift-partial" is the suffix the app used before it was renamed.
            for name in names where name.hasSuffix(".winnow-partial") || name.hasSuffix(".sift-partial") {
                try? fm.removeItem(at: dir.appendingPathComponent(name))
            }
        }
    }

    // MARK: Delete from card

    /// Files safe to delete: only sources whose copies were verified in this import,
    /// plus every file of the given rejects if the user ticked the box.
    static func deletionPlan(result: ImportResult, rejects: [Photo] = []) -> [URL] {
        var urls = result.verified.flatMap { $0.verified.map(\.source) }
        urls += rejects.flatMap(\.files)
        var seen = Set<URL>()
        return urls.filter { seen.insert($0.standardizedFileURL).inserted }
    }

    /// Deletes with removeItem (not the Trash) so the space is freed on the card.
    /// Verified sources are only deleted if their size still matches what was copied.
    static func delete(_ urls: [URL], verified: [VerifiedFile]) -> (deleted: [URL], failed: [URL]) {
        let fm = FileManager.default
        let sizes = Dictionary(verified.map { ($0.source.standardizedFileURL, $0.size) }, uniquingKeysWith: { a, _ in a })
        var deleted: [URL] = [], failed: [URL] = []
        for url in urls {
            if let expected = sizes[url.standardizedFileURL] {
                let now = (try? fm.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
                guard now == expected else { failed.append(url); continue }
            }
            do {
                try fm.removeItem(at: url)
                deleted.append(url)
            } catch {
                failed.append(url)
            }
        }
        return (deleted, failed)
    }
}

/// Streamed copy and SHA-256 with POSIX I/O.
enum FileIO {
    static func sha256(of url: URL, chunkSize: Int = 4 << 20) throws -> String {
        let fd = open(url.path, O_RDONLY)
        guard fd >= 0 else { throw ImportError.io(url.lastPathComponent, errno) }
        defer { close(fd) }
        _ = fcntl(fd, F_NOCACHE, 1)  // read back from storage, not the page cache
        var hasher = SHA256()
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            let n = read(fd, buffer.baseAddress, chunkSize)
            if n < 0 {
                if errno == EINTR { continue }
                throw ImportError.io(url.lastPathComponent, errno)
            }
            if n == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[0..<n]))
        }
        return hasher.finalize().hexString
    }

    /// Copies source to dest (which must not exist), returning the SHA-256 of the bytes read from the source.
    static func copy(from source: URL, to dest: URL, chunkSize: Int = 4 << 20) throws -> String {
        let name = source.lastPathComponent
        let input = open(source.path, O_RDONLY)
        guard input >= 0 else { throw ImportError.io(name, errno) }
        defer { close(input) }
        let output = open(dest.path, O_WRONLY | O_CREAT | O_EXCL, 0o644)
        guard output >= 0 else { throw ImportError.io(dest.lastPathComponent, errno) }
        var closed = false
        defer { if !closed { close(output) } }
        _ = fcntl(input, F_NOCACHE, 1)
        _ = fcntl(output, F_NOCACHE, 1)

        var hasher = SHA256()
        let buffer = UnsafeMutableRawBufferPointer.allocate(byteCount: chunkSize, alignment: 16)
        defer { buffer.deallocate() }
        while true {
            let n = read(input, buffer.baseAddress, chunkSize)
            if n < 0 {
                if errno == EINTR { continue }
                throw ImportError.io(name, errno)
            }
            if n == 0 { break }
            hasher.update(bufferPointer: UnsafeRawBufferPointer(rebasing: buffer[0..<n]))
            var written = 0
            while written < n {
                let w = write(output, buffer.baseAddress! + written, n - written)
                if w < 0 {
                    if errno == EINTR { continue }
                    throw ImportError.io(dest.lastPathComponent, errno)
                }
                written += w
            }
        }
        if fcntl(output, F_FULLFSYNC) != 0 { _ = fsync(output) }
        closed = true
        guard close(output) == 0 else { throw ImportError.io(dest.lastPathComponent, errno) }
        return hasher.finalize().hexString
    }
}

extension Digest {
    var hexString: String { map { String(format: "%02x", $0) }.joined() }
}

enum Lightroom {
    static let bundleIDs = ["com.adobe.LightroomClassicCC7", "com.adobe.LightroomClassic"]

    static var appURL: URL? {
        bundleIDs.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    static func open(_ folder: URL) {
        guard let app = appURL else { return }
        NSWorkspace.shared.open([folder], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }
}
