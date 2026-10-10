import Foundation

enum CardScanner {
    static let rawExtensions: Set<String> = ["raf"]
    static let imageExtensions: Set<String> = ["jpg", "jpeg", "hif", "heif", "heic"]

    enum ScanError: LocalizedError {
        case unreadable(URL)
        var errorDescription: String? {
            switch self {
            case .unreadable(let url): "Sift can't read \(url.lastPathComponent)."
            }
        }
    }

    /// Scans a card (anything with DCIM/) or a plain folder.
    /// On a card it walks DCIM/*/; on a folder it walks the folder and its subfolders.
    static func scan(root: URL, fileManager: FileManager = .default) throws -> [Photo] {
        let dcim = root.appendingPathComponent("DCIM", isDirectory: true)
        var isDir: ObjCBool = false
        if fileManager.fileExists(atPath: dcim.path, isDirectory: &isDir), isDir.boolValue {
            let subfolders = try fileManager.contentsOfDirectory(
                at: dcim, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            var photos: [Photo] = []
            for folder in subfolders {
                let files = (try? fileManager.contentsOfDirectory(
                    at: folder, includingPropertiesForKeys: resourceKeys, options: [.skipsHiddenFiles])) ?? []
                photos += group(files: files, folder: folder.lastPathComponent)
            }
            return sorted(photos)
        }

        guard let enumerator = fileManager.enumerator(
            at: root, includingPropertiesForKeys: resourceKeys + [.isDirectoryKey],
            options: [.skipsHiddenFiles, .skipsPackageDescendants])
        else { throw ScanError.unreadable(root) }

        var byFolder: [String: [URL]] = [:]
        let rootPath = root.standardizedFileURL.path
        for case let url as URL in enumerator {
            guard isSupported(url) else { continue }
            let dir = url.deletingLastPathComponent().standardizedFileURL.path
            var relative = String(dir.dropFirst(rootPath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            if relative.isEmpty { relative = root.lastPathComponent }
            byFolder[relative, default: []].append(url)
        }
        var photos: [Photo] = []
        for (folder, files) in byFolder { photos += group(files: files, folder: folder) }
        return sorted(photos)
    }

    private static let resourceKeys: [URLResourceKey] = [
        .fileSizeKey, .creationDateKey, .contentModificationDateKey, .isRegularFileKey,
    ]

    static func isSupported(_ url: URL) -> Bool {
        let name = url.lastPathComponent
        guard !name.hasPrefix(".") else { return false }  // includes AppleDouble "._" files on exFAT
        let ext = url.pathExtension.lowercased()
        return rawExtensions.contains(ext) || imageExtensions.contains(ext)
    }

    /// Groups files by basename, case-insensitively: DSCF4503.RAF + DSCF4503.JPG = one photo.
    static func group(files: [URL], folder: String) -> [Photo] {
        var byKey: [String: Photo] = [:]
        for url in files where isSupported(url) {
            let values = try? url.resourceValues(forKeys: Set(resourceKeys))
            if values?.isRegularFile == false { continue }
            let basename = url.deletingPathExtension().lastPathComponent
            let id = Photo.makeID(folder: folder, basename: basename)
            let size = Int64(values?.fileSize ?? 0)
            let date = values?.creationDate ?? values?.contentModificationDate ?? .distantPast
            var photo = byKey[id] ?? Photo(id: id, basename: basename, folder: folder, fileDate: date)
            let ext = url.pathExtension.lowercased()
            if rawExtensions.contains(ext) {
                photo.raf = url
                photo.rafSize = size
            } else if photo.jpg == nil || ext == "jpg" || ext == "jpeg" {
                // Prefer JPG over HEIF if a camera somehow wrote both.
                photo.jpg = url
                photo.jpgSize = size
            }
            photo.fileDate = min(photo.fileDate, date)
            byKey[id] = photo
        }
        return Array(byKey.values)
    }

    static func sorted(_ photos: [Photo]) -> [Photo] {
        photos.sorted {
            if $0.fileDate != $1.fileDate { return $0.fileDate < $1.fileDate }
            if $0.basename.lowercased() != $1.basename.lowercased() {
                return $0.basename.lowercased() < $1.basename.lowercased()
            }
            return $0.folder < $1.folder
        }
    }
}
