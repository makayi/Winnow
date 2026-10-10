import AppKit
import Observation

struct SourceInfo: Hashable, Sendable, Identifiable {
    enum Kind: Sendable { case card, folder }
    let kind: Kind
    let rootURL: URL
    let cardID: String
    let name: String

    var id: String { cardID }
    var isCard: Bool { kind == .card }
}

/// Watches for camera cards: removable volumes with a DCIM folder.
@MainActor @Observable
final class VolumeWatcher {
    private(set) var cards: [SourceInfo] = []
    @ObservationIgnored var onMount: ((SourceInfo) -> Void)?
    @ObservationIgnored var onUnmount: ((URL) -> Void)?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    func start() {
        let keys: [URLResourceKey] = [.volumeIsRemovableKey, .volumeIsEjectableKey]
        let volumes = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        cards = volumes.compactMap(Self.cardInfo(forVolume:))

        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didMountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self?.mounted(url) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didUnmountNotification, object: nil, queue: .main) { [weak self] note in
            guard let url = note.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
            MainActor.assumeIsolated { self?.unmounted(url) }
        })
    }

    private func mounted(_ url: URL) {
        guard let card = Self.cardInfo(forVolume: url) else { return }
        cards.removeAll { $0.rootURL.standardizedFileURL == url.standardizedFileURL }
        cards.append(card)
        onMount?(card)
    }

    private func unmounted(_ url: URL) {
        cards.removeAll { $0.rootURL.standardizedFileURL == url.standardizedFileURL }
        onUnmount?(url)
    }

    static func cardInfo(forVolume url: URL) -> SourceInfo? {
        let values = try? url.resourceValues(forKeys: [
            .volumeIsRemovableKey, .volumeIsEjectableKey, .volumeUUIDStringKey, .volumeNameKey,
            .volumeTotalCapacityKey, .volumeIsInternalKey,
        ])
        let removable = values?.volumeIsRemovable == true || values?.volumeIsEjectable == true
        guard removable, hasDCIM(url) else { return nil }
        let name = values?.volumeName ?? url.lastPathComponent
        let id = values?.volumeUUIDString ?? "\(name)-\(values?.volumeTotalCapacity ?? 0)"
        return SourceInfo(kind: .card, rootURL: url, cardID: id, name: name)
    }

    /// A folder chosen with File > Open Folder. If it is a card's root, treat it as the card.
    static func sourceInfo(forFolder url: URL) -> SourceInfo {
        if let card = cardInfo(forVolume: url) { return card }
        #if DEBUG
        // Lets a scratch folder with DCIM/ stand in for a card (delete prompt, eject UI).
        if UserDefaults.standard.bool(forKey: "folderIsCard"), hasDCIM(url) {
            return SourceInfo(kind: .card, rootURL: url, cardID: CardStore.folderID(for: url), name: url.lastPathComponent)
        }
        #endif
        return SourceInfo(kind: .folder, rootURL: url, cardID: CardStore.folderID(for: url), name: url.lastPathComponent)
    }

    static func hasDCIM(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("DCIM").path, isDirectory: &isDir) && isDir.boolValue
    }

    static func eject(_ url: URL) async throws {
        try await Task.detached {
            try NSWorkspace.shared.unmountAndEjectDevice(at: url)
        }.value
    }
}
