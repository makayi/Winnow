import Foundation
import Testing
@testable import Winnow

@Suite struct CardStoreTests {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent("WinnowStore-\(UUID().uuidString)")

    @Test func missingCardStartsEmpty() {
        let store = CardStore(directory: dir)
        let state = store.load(cardID: "nothing-here")
        #expect(state.flags.isEmpty)
        #expect(state.imports.isEmpty)
    }

    @Test func flagsAndImportsSurviveReload() throws {
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = CardStore(directory: dir)
        var state = CardState(cardID: "1234-ABCD")
        state.flags = ["100_fuji/dscf0001": .pick, "100_fuji/dscf0002": .reject]
        state.imports = [ImportRecord(photoID: "100_fuji/dscf0001", basename: "DSCF0001", fileName: "DSCF0001.RAF",
                                      size: 42, sha256: "abc", destinationPath: "/tmp/x/DSCF0001.RAF",
                                      date: Date(timeIntervalSince1970: 1_000_000))]
        store.saveInBackground(state)
        store.flush()

        let reloaded = CardStore(directory: dir).load(cardID: "1234-ABCD")
        #expect(reloaded == state)
    }

    @Test func cardIDsBecomeSafeFileNames() {
        let store = CardStore(directory: dir)
        #expect(store.fileURL(for: "NO NAME/../x").lastPathComponent == "NO_NAME____x.json")
    }

    @Test func folderIDIsStable() {
        let a = CardStore.folderID(for: URL(fileURLWithPath: "/Users/me/Pictures/Trip"))
        let b = CardStore.folderID(for: URL(fileURLWithPath: "/Users/me/Pictures/Trip/"))
        #expect(a == b)
        #expect(a.hasPrefix("folder-"))
    }
}
