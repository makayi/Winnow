import Foundation

/// The app used to be called Sift. Brings over its per-card state and settings once.
enum LegacyMigration {
    static func run(defaults: UserDefaults = .standard, fileManager: FileManager = .default) {
        guard !defaults.bool(forKey: "migratedFromSift") else { return }
        defer { defaults.set(true, forKey: "migratedFromSift") }

        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let old = support.appendingPathComponent("Sift/cards", isDirectory: true)
        let new = CardStore.defaultDirectory
        if let files = try? fileManager.contentsOfDirectory(at: old, includingPropertiesForKeys: nil) {
            try? fileManager.createDirectory(at: new, withIntermediateDirectories: true)
            for file in files where file.pathExtension == "json" {
                let target = new.appendingPathComponent(file.lastPathComponent)
                if !fileManager.fileExists(atPath: target.path) { try? fileManager.copyItem(at: file, to: target) }
            }
        }

        if let legacy = UserDefaults(suiteName: "com.mbuyumakayi.Sift") {
            for key in ["importOptions", "thumbnailSize"] where defaults.object(forKey: key) == nil {
                if let value = legacy.object(forKey: key) { defaults.set(value, forKey: key) }
            }
        }
    }
}
