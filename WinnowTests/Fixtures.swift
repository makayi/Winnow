import Foundation
@testable import Winnow

/// A temporary folder that looks like a camera card: <root>/DCIM/100_FUJI/...
struct FakeCard {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("WinnowTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("DCIM/100_FUJI"), withIntermediateDirectories: true)
    }

    var dcim: URL { root.appendingPathComponent("DCIM") }

    @discardableResult
    func add(_ name: String, folder: String = "100_FUJI", bytes: Int = 64 * 1024, date: Date? = nil, seed: UInt8 = 1) throws -> URL {
        let dir = dcim.appendingPathComponent(folder, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let url = dir.appendingPathComponent(name)
        var data = Data(count: bytes)
        for i in 0..<bytes { data[i] = UInt8(truncatingIfNeeded: i &* 31 &+ Int(seed)) }
        try data.write(to: url)
        if let date {
            try FileManager.default.setAttributes([.creationDate: date, .modificationDate: date], ofItemAtPath: url.path)
        }
        return url
    }

    func makeDestination() -> URL {
        root.deletingLastPathComponent().appendingPathComponent("WinnowDest-\(UUID().uuidString)", isDirectory: true)
    }

    func cleanUp() {
        try? FileManager.default.removeItem(at: root)
    }
}

func allFiles(in dir: URL) -> [String] {
    let base = dir.resolvingSymlinksInPath().path + "/"
    guard let e = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: nil) else { return [] }
    return e.compactMap { ($0 as? URL)?.resolvingSymlinksInPath().path.replacingOccurrences(of: base, with: "") }.sorted()
}

func date(_ s: String) -> Date {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}
