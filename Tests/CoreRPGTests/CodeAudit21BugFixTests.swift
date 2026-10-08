// @copyright André Trettin

import Foundation
import Testing
import UniformTypeIdentifiers

@testable import CoreRPG

/// Regression tests for CODE_AUDIT_21 §5 findings in CoreRPG.
@Suite("CODE_AUDIT_21 §5 — core")
struct CodeAudit21BugFixTests {
    // MARK: - §5.7

    @Test("Duplicate rows are ordered by their CloudKit record name, a row without one last")
    func duplicateRowOrder() {
        let localOnly: (recordName: String?, localURI: String) = (nil, "x-coredata://A/Item/p1")
        let recordB: (recordName: String?, localURI: String) = ("B", "x-coredata://A/Item/p2")
        let recordA: (recordName: String?, localURI: String) = ("A", "x-coredata://A/Item/p9")

        // The record name decides, on every device alike; the local URI differs per device.
        #expect(DuplicateRowOrder.precedes(recordA, recordB))
        #expect(!DuplicateRowOrder.precedes(recordB, recordA))
        // A row that never left this device is the one removed.
        #expect(DuplicateRowOrder.precedes(recordB, localOnly))
        #expect(!DuplicateRowOrder.precedes(localOnly, recordA))
        // Without record names (a local store) the local URI still gives one answer.
        #expect(DuplicateRowOrder.precedes(localOnly, (nil, "x-coredata://A/Item/p5")))
    }

    // MARK: - §5.14

    @MainActor
    @Test("The list of game-memory files survives the run that wrote it")
    func gameMemoryFilesArePersisted() {
        let key = "gameMemoryFilesTest.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let file = FileUrl(fileId: UUID(), url: URL(filePath: "/Maps/Cave.jpg"), location: .newCloud, module: "photos", relativeUrl: nil)

        let firstRun = FileUrlDataModel(gameMemoryFilesKey: key)
        #expect(firstRun.leftoverGameMemoryFiles.isEmpty)
        firstRun.gameMemoryFiles.append(file)

        // The app was killed before the game ended: the next run finds the list.
        let secondRun = FileUrlDataModel(gameMemoryFilesKey: key)
        #expect(secondRun.leftoverGameMemoryFiles.map(\.fileId) == [file.fileId])
        #expect(secondRun.leftoverGameMemoryFiles.first?.rawUrl.lastPathComponent == "Cave.jpg")
        #expect(secondRun.gameMemoryFiles.isEmpty)

        // The launch cleanup takes it once.
        #expect(secondRun.takeLeftoverGameMemoryFiles().count == 1)
        #expect(FileUrlDataModel(gameMemoryFilesKey: key).leftoverGameMemoryFiles.isEmpty)
    }

    @MainActor
    @Test("A game that ends normally leaves no list behind")
    func endedGameClearsPersistedList() {
        let key = "gameMemoryFilesTest.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let model = FileUrlDataModel(gameMemoryFilesKey: key)
        model.gameMemoryFiles.append(FileUrl(fileId: UUID(), url: URL(filePath: "/a.jpg"), location: .newCloud, module: "photos", relativeUrl: nil))
        #expect(UserDefaults.standard.data(forKey: key) != nil)

        model.gameMemoryFiles = []

        #expect(UserDefaults.standard.data(forKey: key) == nil)
    }

    // MARK: - §5.15

    private func storedFile(named name: String, text: String, module: String, with sut: FileUrlDataController) async throws -> FileUrl {
        let fileId = UUID()
        var unconverted = FileUrl(fileId: fileId, url: URL(string: "/")!.appending(path: name), location: .newCloud, module: module, relativeUrl: nil)
        unconverted.resetData(Data(text.utf8))
        return try #require(try await sut.createNewFileUrl(
            fileId: fileId,
            unconvertedFileUrl: unconverted,
            pathExtension: "test",
            requireDurableStorage: true
        ))
    }

    @Test("Moving a file to where it already is changes nothing")
    func moveToSamePathIsNoMove() async throws {
        let module = "MoveSameModule-\(UUID().uuidString)"
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        let file = try await storedFile(named: "Folder/Rules.test", text: "rules", module: module, with: sut)

        let moved = try await sut.move(fileUrl: file, to: "Folder/Rules")

        #expect(moved == nil)
        let location = try #require(sut.storedLocation(of: file))
        #expect(location.lastPathComponent == "Rules.test")
        #expect(FileManager.default.fileExists(atPath: location.path(percentEncoded: false)))
    }

    @Test("Folder and item names with #, ? and % are kept as they are")
    func moveKeepsSpecialCharacters() async throws {
        let module = "MoveNamesModule-\(UUID().uuidString)"
        let sut = await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
        let file = try await storedFile(named: "Rules.test", text: "rules", module: module, with: sut)

        let moved = try #require(try await sut.move(fileUrl: file, to: "Maps #1?/Level %41"))

        let location = try #require(sut.storedLocation(of: moved))
        #expect(location.lastPathComponent == "Level %41.test")
        #expect(location.deletingLastPathComponent().lastPathComponent == "Maps #1?")
        #expect(try String(contentsOf: location, encoding: .utf8) == "rules")
        #expect(sut.storedLocation(of: file).map { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) } == false)
    }

    // MARK: - §5.16

    @Test("The actor id is kept on its device and replaced on another")
    func actorIdIsBoundToTheDevice() throws {
        let suite = "LocalActorIdTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }

        let created = LocalActorId.resolve(defaults: defaults, deviceMarker: "device-1")
        #expect(LocalActorId.resolve(defaults: defaults, deviceMarker: "device-1") == created)
        // The marker cannot be read right now (locked Keychain): the stored id stays.
        #expect(LocalActorId.resolve(defaults: defaults, deviceMarker: nil) == created)
        // The defaults were copied to another device.
        let other = LocalActorId.resolve(defaults: defaults, deviceMarker: "device-2")
        #expect(other != created)
        #expect(LocalActorId.resolve(defaults: defaults, deviceMarker: "device-2") == other)
    }

    @Test("An actor id from before the device marker is kept and bound to this device")
    func actorIdFromBeforeTheMarkerIsKept() throws {
        let suite = "LocalActorIdTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("existing-actor", forKey: LocalActorId.actorKey)

        #expect(LocalActorId.resolve(defaults: defaults, deviceMarker: "device-1") == "existing-actor")
        #expect(defaults.string(forKey: LocalActorId.markerKey) == "device-1")
    }

    @Test("A decoded clock at the maximum is capped, so a later clock still exists")
    func decodedClockIsCapped() throws {
        let json = #"{"clock": 1.7976931348623157e308, "actorId": "a"}"#
        let timestamp = try JSONDecoder().decode(WallclockTimestamp<String>.self, from: Data(json.utf8))

        #expect(timestamp.clock == WallclockTimestamp<String>.maximumDecodedClock)
        #expect(timestamp.clock.nextUp.isFinite)
        #expect(timestamp.clock.nextUp > timestamp.clock)
    }
}
