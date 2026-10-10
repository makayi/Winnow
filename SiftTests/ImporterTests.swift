import Foundation
import Testing
@testable import Sift

@Suite struct ImporterTests {
    func options(_ dest: URL, layout: FolderLayout = .byDate, files: FileTypeChoice = .both) -> ImportOptions {
        var o = ImportOptions()
        o.destinationPath = dest.path
        o.layout = layout
        o.fileTypes = files
        return o
    }

    func items(_ card: FakeCard, taken: Date = date("2026-10-10 12:00")) throws -> [ImportItem] {
        try CardScanner.scan(root: card.root).map { ImportItem(photo: $0, captureDate: taken) }
    }

    @Test func copiesPairsIntoDateFoldersAndVerifies() throws {
        let card = try FakeCard()
        let dest = card.makeDestination()
        defer { card.cleanUp(); try? FileManager.default.removeItem(at: dest) }
        let shot = date("2026-10-09 18:30")
        try card.add("DSCF4503.RAF", bytes: 300_000, date: shot)
        try card.add("DSCF4503.JPG", bytes: 90_000, date: shot)

        let result = Importer().run(items: try items(card), options: options(dest))
        #expect(result.verified.count == 1)
        #expect(result.failed.isEmpty)
        #expect(allFiles(in: dest) == ["2026", "2026/2026-10-10", "2026/2026-10-10/DSCF4503.JPG", "2026/2026-10-10/DSCF4503.RAF"])

        let copied = dest.appendingPathComponent("2026/2026-10-10/DSCF4503.RAF")
        let attrs = try FileManager.default.attributesOfItem(atPath: copied.path)
        #expect(attrs[.modificationDate] as? Date == shot)
        #expect(try FileIO.sha256(of: copied) == result.verified[0].verified.first { $0.destination == copied }?.sha256)
    }

    @Test func keepCardFoldersAndSingleFolderLayouts() throws {
        let card = try FakeCard()
        let dest = card.makeDestination()
        defer { card.cleanUp(); try? FileManager.default.removeItem(at: dest) }
        try card.add("DSCF0001.JPG", folder: "101_FUJI")

        _ = Importer().run(items: try items(card), options: options(dest, layout: .keepCardFolders))
        #expect(FileManager.default.fileExists(atPath: dest.appendingPathComponent("101_FUJI/DSCF0001.JPG").path))

        let flat = card.makeDestination()
        defer { try? FileManager.default.removeItem(at: flat) }
        _ = Importer().run(items: try items(card), options: options(flat, layout: .singleFolder))
        #expect(allFiles(in: flat) == ["DSCF0001.JPG"])
    }

    @Test func fileTypeChoiceFallsBackWhenTypeIsMissing() throws {
        let card = try FakeCard()
        let dest = card.makeDestination()
        defer { card.cleanUp(); try? FileManager.default.removeItem(at: dest) }
        try card.add("DSCF0001.RAF")
        try card.add("DSCF0001.JPG")
        try card.add("DSCF0002.JPG")

        let result = Importer().run(items: try items(card), options: options(dest, layout: .singleFolder, files: .rafOnly))
        #expect(result.verified.count == 2)
        #expect(allFiles(in: dest) == ["DSCF0001.RAF", "DSCF0002.JPG"])
    }

    @Test func corruptedCopyIsRetriedThenFailsAndIsNeverDeleted() throws {
        let card = try FakeCard()
        let dest = card.makeDestination()
        defer { card.cleanUp(); try? FileManager.default.removeItem(at: dest) }
        let bad = try card.add("DSCF0001.RAF")
        try card.add("DSCF0002.RAF", seed: 2)

        let attempts = Counter()
        let importer = Importer(afterCopy: { partial in
            guard partial.lastPathComponent.contains("DSCF0001") else { return }
            attempts.increment()
            let h = try FileHandle(forWritingTo: partial)
            try h.seek(toOffset: 10)
            try h.write(contentsOf: Data([0xFF, 0x00, 0xFF]))
            try h.close()
        })
        let result = importer.run(items: try items(card), options: options(dest, layout: .singleFolder))

        #expect(attempts.value == 2)  // first try + one retry
        #expect(result.failed.map(\.photo.basename) == ["DSCF0001"])
        #expect(result.verified.map(\.photo.basename) == ["DSCF0002"])
        #expect(allFiles(in: dest) == ["DSCF0002.RAF"])  // no partial, no bad copy

        let plan = Importer.deletionPlan(result: result)
        #expect(!plan.contains(bad))
        let outcome = Importer.delete(plan, verified: result.verified.flatMap(\.verified))
        #expect(outcome.deleted.map(\.lastPathComponent) == ["DSCF0002.RAF"])
        #expect(FileManager.default.fileExists(atPath: bad.path))
    }

    @Test func sameContentIsAlreadyImportedDifferentContentGetsSuffix() throws {
        let card = try FakeCard()
        let dest = card.makeDestination()
        defer { card.cleanUp(); try? FileManager.default.removeItem(at: dest) }
        try card.add("DSCF0001.JPG", seed: 7)
        try card.add("DSCF0002.JPG", seed: 8)
        try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: card.dcim.appendingPathComponent("100_FUJI/DSCF0001.JPG"),
                                         to: dest.appendingPathComponent("DSCF0001.JPG"))
        // A different photo that happens to share the name (e.g. after the counter wrapped).
        try Data(repeating: 9, count: 64 * 1024).write(to: dest.appendingPathComponent("DSCF0002.JPG"))

        let result = Importer().run(items: try items(card), options: options(dest, layout: .singleFolder))
        #expect(result.verified.count == 2)
        let outcomes = Dictionary(uniqueKeysWithValues: result.verified.flatMap(\.verified).map { ($0.source.lastPathComponent, $0) })
        #expect(outcomes["DSCF0001.JPG"]?.outcome == .alreadyImported)
        #expect(outcomes["DSCF0002.JPG"]?.outcome == .copied)
        #expect(outcomes["DSCF0002.JPG"]?.destination.lastPathComponent == "DSCF0002-1.JPG")
        #expect(allFiles(in: dest) == ["DSCF0001.JPG", "DSCF0002-1.JPG", "DSCF0002.JPG"])
    }

    @Test func stopMidwayKeepsFinishedFilesAndLeavesNoPartials() throws {
        let card = try FakeCard()
        let dest = card.makeDestination()
        defer { card.cleanUp(); try? FileManager.default.removeItem(at: dest) }
        for i in 1...5 { try card.add(String(format: "DSCF%04d.JPG", i), date: date("2026-10-10 10:0\(i)")) }

        let stop = StopSignal()
        let result = Importer().run(items: try items(card), options: options(dest, layout: .singleFolder), stop: stop,
                                    photoFinished: { r in if r.photo.basename == "DSCF0002" { stop.stop() } })
        #expect(result.stopped)
        #expect(result.verified.map(\.photo.basename) == ["DSCF0001", "DSCF0002"])
        #expect(result.failed.isEmpty)
        #expect(result.skippedCount == 3)
        #expect(allFiles(in: dest) == ["DSCF0001.JPG", "DSCF0002.JPG"])
    }

    @Test func pulledCardReportsFailuresAndLeavesNoPartials() throws {
        let card = try FakeCard()
        let dest = card.makeDestination()
        defer { card.cleanUp(); try? FileManager.default.removeItem(at: dest) }
        try card.add("DSCF0001.RAF")
        try card.add("DSCF0001.JPG")
        try card.add("DSCF0002.RAF")
        let planned = try items(card)
        try FileManager.default.removeItem(at: card.dcim)  // the card is gone

        let result = Importer().run(items: planned, options: options(dest, layout: .singleFolder))
        #expect(result.verified.isEmpty)
        #expect(Set(result.failed.map(\.photo.basename)) == ["DSCF0001", "DSCF0002"])
        #expect(allFiles(in: dest).allSatisfy { !$0.hasSuffix(".sift-partial") })
        #expect(Importer.deletionPlan(result: result).isEmpty)
    }

    @Test func deletionPlanCoversBothFilesOfVerifiedPairsAndOptionalRejects() throws {
        let card = try FakeCard()
        let dest = card.makeDestination()
        defer { card.cleanUp(); try? FileManager.default.removeItem(at: dest) }
        try card.add("DSCF0001.RAF")
        try card.add("DSCF0001.JPG")
        try card.add("DSCF0002.RAF")
        try card.add("DSCF0003.JPG")  // not imported, not rejected: must survive
        let all = try CardScanner.scan(root: card.root)
        let pick = all.filter { $0.basename == "DSCF0001" }
        let reject = all.filter { $0.basename == "DSCF0002" }

        let result = Importer().run(items: pick.map { ImportItem(photo: $0, captureDate: Date()) },
                                    options: options(dest, layout: .singleFolder))
        let withoutRejects = Importer.deletionPlan(result: result)
        #expect(Set(withoutRejects.map(\.lastPathComponent)) == ["DSCF0001.RAF", "DSCF0001.JPG"])

        let plan = Importer.deletionPlan(result: result, rejects: reject)
        let outcome = Importer.delete(plan, verified: result.verified.flatMap(\.verified))
        #expect(outcome.failed.isEmpty)
        #expect(try CardScanner.scan(root: card.root).map(\.basename) == ["DSCF0003"])
    }

    @Test func deleteRefusesASourceThatChangedSinceCopying() throws {
        let card = try FakeCard()
        let dest = card.makeDestination()
        defer { card.cleanUp(); try? FileManager.default.removeItem(at: dest) }
        let src = try card.add("DSCF0001.JPG")
        let result = Importer().run(items: try items(card), options: options(dest, layout: .singleFolder))
        try Data(count: 10).write(to: src)  // something else now lives at this path

        let outcome = Importer.delete(Importer.deletionPlan(result: result), verified: result.verified.flatMap(\.verified))
        #expect(outcome.deleted.isEmpty)
        #expect(FileManager.default.fileExists(atPath: src.path))
    }
}

final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var n = 0
    var value: Int { lock.withLock { n } }
    func increment() { lock.withLock { n += 1 } }
}
