import CryptoKit
import Foundation

/// Per-card state persisted as JSON so flags survive eject and reinsert.
struct CardState: Codable, Equatable, Sendable {
    var version = 1
    var cardID: String
    var flags: [String: Flag] = [:]
    var imports: [ImportRecord] = []
}

final class CardStore: @unchecked Sendable {
    let directory: URL
    private let queue = DispatchQueue(label: "Sift.CardStore")

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("Sift/cards", isDirectory: true)
    }

    init(directory: URL = CardStore.defaultDirectory) {
        self.directory = directory
    }

    func fileURL(for cardID: String) -> URL {
        let safe = cardID.map { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" ? $0 : "_" }
        return directory.appendingPathComponent(String(safe)).appendingPathExtension("json")
    }

    func load(cardID: String) -> CardState {
        let url = fileURL(for: cardID)
        guard let data = try? Data(contentsOf: url) else { return CardState(cardID: cardID) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode(CardState.self, from: data)) ?? CardState(cardID: cardID)
    }

    func save(_ state: CardState) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(state)
        try data.write(to: fileURL(for: state.cardID), options: .atomic)
    }

    /// Saves off the main thread; writes stay in order.
    func saveInBackground(_ state: CardState) {
        queue.async { [self] in try? save(state) }
    }

    /// Blocks until queued background saves are written. Used by tests.
    func flush() { queue.sync {} }

    /// Identity for a folder opened with File > Open Folder.
    static func folderID(for url: URL) -> String {
        let digest = SHA256.hash(data: Data(url.standardizedFileURL.path.utf8))
        return "folder-" + digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}
