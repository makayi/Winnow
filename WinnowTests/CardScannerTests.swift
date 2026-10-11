import Foundation
import Testing
@testable import Winnow

@Suite struct CardScannerTests {
    @Test func pairsRAFAndJPGCaseInsensitively() throws {
        let card = try FakeCard()
        defer { card.cleanUp() }
        try card.add("DSCF4503.RAF", bytes: 1000)
        try card.add("dscf4503.jpg", bytes: 200)

        let photos = try CardScanner.scan(root: card.root)
        #expect(photos.count == 1)
        let p = try #require(photos.first)
        #expect(p.raf?.lastPathComponent == "DSCF4503.RAF")
        #expect(p.jpg?.lastPathComponent == "dscf4503.jpg")
        #expect(p.byteSize == 1200)
        #expect(p.kindLabel == "RAF+JPG")
        #expect(p.folder == "100_FUJI")
        #expect(p.id == "100_fuji/dscf4503")
    }

    @Test func allowsRAFOnlyAndJPGOnlyAndHEIF() throws {
        let card = try FakeCard()
        defer { card.cleanUp() }
        try card.add("DSCF0001.RAF")
        try card.add("DSCF0002.JPG")
        try card.add("DSCF0003.HIF")

        let photos = try CardScanner.scan(root: card.root)
        let byName = Dictionary(uniqueKeysWithValues: photos.map { ($0.basename, $0) })
        #expect(byName["DSCF0001"]?.kindLabel == "RAF")
        #expect(byName["DSCF0002"]?.kindLabel == "JPG")
        #expect(byName["DSCF0003"]?.kindLabel == "HIF")
    }

    @Test func skipsAppleDoubleAndUnsupportedFiles() throws {
        let card = try FakeCard()
        defer { card.cleanUp() }
        try card.add("DSCF0001.JPG")
        try card.add("._DSCF0001.JPG")
        try card.add("DSCF0002.MOV")
        try card.add("NOTES.TXT")

        let photos = try CardScanner.scan(root: card.root)
        #expect(photos.map(\.basename) == ["DSCF0001"])
    }

    @Test func walksEveryDCIMFolderAndSortsByDate() throws {
        let card = try FakeCard()
        defer { card.cleanUp() }
        try card.add("DSCF0100.JPG", folder: "101_FUJI", date: date("2026-10-10 09:00"))
        try card.add("DSCF9999.JPG", folder: "100_FUJI", date: date("2026-10-10 08:00"))
        try card.add("DSCF0001.JPG", folder: "100_FUJI", date: date("2026-10-10 08:00"))

        let photos = try CardScanner.scan(root: card.root)
        #expect(photos.map(\.basename) == ["DSCF0001", "DSCF9999", "DSCF0100"])
        #expect(Set(photos.map(\.folder)) == ["100_FUJI", "101_FUJI"])
    }

    @Test func scansAPlainFolderWithoutDCIM() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("WinnowFolder-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("trip"), withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("A.JPG"))
        try Data([1]).write(to: root.appendingPathComponent("trip/B.RAF"))

        let photos = try CardScanner.scan(root: root)
        #expect(Set(photos.map(\.basename)) == ["A", "B"])
        #expect(photos.first { $0.basename == "B" }?.folder == "trip")
        #expect(photos.first { $0.basename == "A" }?.folder == root.lastPathComponent)
    }
}
