// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// Picked files that share a name must each keep their own bytes, also when the imports run at
/// the same time. See CODE_AUDIT §5.1.
@Suite("Picker import name race")
struct PickerImportNameRaceTests {
    /// A controller on a module folder of its own, removed again by the test.
    private func makeController() -> CloudDocumentController {
        // The module name loses its last character, so the folder is `racetest-<uuid>`.
        CloudDocumentController(modulePath: "RaceTest-\(UUID().uuidString)s")
    }

    private func makeSource(content: String, in directory: URL, name: String = "pick.txt") throws -> URL {
        let folder = directory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try Data(content.utf8).write(to: url)
        return url
    }

    @Test("Concurrent picks of equally named files get distinct destinations and keep their bytes")
    func concurrentPicksDoNotOverwrite() async throws {
        let controller = makeController()
        let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: scratch)
            try? FileManager.default.removeItem(at: controller.moduleUrl)
        }
        let contents = (0..<6).map { "content-\($0)" }
        let sources = try contents.map { try makeSource(content: $0, in: scratch) }

        let destinations = try await withThrowingTaskGroup(of: (Int, URL).self) { group in
            for (index, source) in sources.enumerated() {
                group.addTask { (index, try await controller.createNameUrl(for: source)) }
            }
            var result: [Int: URL] = [:]
            for try await (index, url) in group { result[index] = url }
            return result
        }

        #expect(Set(destinations.values.map { $0.standardizedFileURL.path(percentEncoded: false) }).count == contents.count)
        for (index, url) in destinations {
            let stored = try String(contentsOf: url, encoding: .utf8)
            #expect(stored == contents[index], "pick \(index) was overwritten")
        }
    }

    @Test("A name taken by a file already stored is skipped, and the stored file stays")
    func takenNameKeepsExistingFile() async throws {
        let controller = makeController()
        let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: scratch)
            try? FileManager.default.removeItem(at: controller.moduleUrl)
        }
        let first = try makeSource(content: "first", in: scratch)
        let second = try makeSource(content: "second", in: scratch)

        let firstDestination = try await controller.createNameUrl(for: first)
        let secondDestination = try await controller.createNameUrl(for: second)

        #expect(firstDestination != secondDestination)
        #expect(try String(contentsOf: firstDestination, encoding: .utf8) == "first")
        #expect(try String(contentsOf: secondDestination, encoding: .utf8) == "second")
    }

    @Test("The copy itself refuses to replace a file that is already there")
    func copyWithoutReplacingThrowsWhenTaken() async throws {
        let controller = makeController()
        let scratch = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        defer {
            try? FileManager.default.removeItem(at: scratch)
            try? FileManager.default.removeItem(at: controller.moduleUrl)
        }
        let first = try makeSource(content: "first", in: scratch)
        let second = try makeSource(content: "second", in: scratch)
        try await controller.copyWithoutReplacing(from: first, to: "taken.txt")

        await #expect(throws: CocoaError.self) {
            try await controller.copyWithoutReplacing(from: second, to: "taken.txt")
        }
        let storedUrl = try #require(controller.fullUrl(filePath: "taken.txt"))
        let stored = try String(contentsOf: storedUrl, encoding: .utf8)
        #expect(stored == "first")
    }

    @Test("An empty module name no longer traps (CODE_AUDIT §5.5)")
    func emptyModuleNameDoesNotTrap() {
        #expect(CloudDocumentController(modulePath: "").modulePath.isEmpty)
        #expect(FileBookmarkController.name(from: "") == "Bookmarks")
        #expect(CloudDocumentController(modulePath: "Photos").modulePath == "photo")
        #expect(FileBookmarkController.name(from: "Photos") == "photoBookmarks")
    }
}
