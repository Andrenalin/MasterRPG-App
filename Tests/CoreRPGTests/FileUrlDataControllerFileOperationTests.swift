// @copyright André Trettin

import Foundation
import Testing
import UniformTypeIdentifiers

@testable import CoreRPG

/// CODE_AUDIT_20 §5.1, §5.3, §5.9, §9.19: duplicating, deleting and replacing files act on the
/// file's real location and never delete a file they were asked to keep.
@Suite("FileUrlDataController - copy, delete and replace")
struct FileUrlDataControllerFileOperationTests {
    private func makeSut(module: String) async -> FileUrlDataController {
        await FileUrlDataController(moduleFolder: module, fileTypes: [.data], filenameExtension: "test")
    }

    private func rootUrl(named name: String) -> URL {
        URL(string: "/")!.appending(component: name)
    }

    /// Creates a stored `.newCloud` file with `text` named `name`.
    private func createFile(_ name: String, text: String, module: String, with sut: FileUrlDataController) async throws -> FileUrl {
        let fileId = UUID()
        var unconverted = FileUrl(fileId: fileId, url: rootUrl(named: name), location: .newCloud, module: module, relativeUrl: nil)
        unconverted.resetData(Data(text.utf8))
        return try #require(try await sut.createNewFileUrl(
            fileId: fileId,
            unconvertedFileUrl: unconverted,
            pathExtension: "test",
            requireDurableStorage: true
        ))
    }

    private func exists(_ fileUrl: FileUrl, in sut: FileUrlDataController) -> Bool {
        guard let url = sut.cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl) else { return false }
        return FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    private func text(of fileUrl: FileUrl, in sut: FileUrlDataController) throws -> String {
        let url = try #require(sut.cloudDocumentController.fullUrl(fileUrl: fileUrl.rawUrl))
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    /// Waits for the detached delete of `fileUrl` to finish.
    private func waitUntilGone(_ fileUrl: FileUrl, in sut: FileUrlDataController) async throws {
        // The deletion queues behind the file-coordination limiter, which on a busy CI machine
        // takes longer than any fixed polling budget, so wait for the deletion itself.
        if let location = sut.storedLocation(of: fileUrl) {
            await PendingFileDeletions.shared.waitUntilFinished(at: CloudDocumentController.canonicalPath(location))
        }
        for _ in 0..<50 where exists(fileUrl, in: sut) {
            try await Task.sleep(for: .milliseconds(20))
        }
    }

    // MARK: - CODE_AUDIT_21 §5.1, §6.1

    @Test("Deleting a file in a folder named Documents removes that file only")
    func deleteInDocumentsFolderKeepsModuleFolder() async throws {
        let module = "DocumentsModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let other = try await createFile("Other-\(UUID().uuidString).test", text: "other", module: module, with: sut)
        let name = "Rules-\(UUID().uuidString).test"
        let inFolder = try await createFile("Documents/\(name)", text: "rules", module: module, with: sut)

        #expect(inFolder.rawUrl.path(percentEncoded: false) == "/Documents/\(name)")
        #expect(try text(of: inFolder, in: sut) == "rules")
        let stored = try #require(sut.storedLocation(of: inFolder))
        #expect(stored.lastPathComponent == name)
        #expect(stored.deletingLastPathComponent().lastPathComponent == "Documents")

        sut.delete(inFolder)
        try await waitUntilGone(inFolder, in: sut)

        #expect(!exists(inFolder, in: sut))
        #expect(try text(of: other, in: sut) == "other", "the module's other files survive")
    }

    @Test("Deleting the last file of a folder removes the empty folders above it, not the module folder")
    func deleteRemovesEmptyFolders() async throws {
        let module = "EmptyFoldersModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let id = UUID().uuidString
        let nested = try await createFile("Top-\(id)/Mid/Deep/Nested.test", text: "nested", module: module, with: sut)
        let sibling = try await createFile("Top-\(id)/Sibling.test", text: "sibling", module: module, with: sut)
        let top = try #require(sut.storedLocation(of: sibling)).deletingLastPathComponent()
        let deep = try #require(sut.storedLocation(of: nested)).deletingLastPathComponent()
        // Finder leaves this in every folder it showed.
        try Data().write(to: deep.appending(path: ".DS_Store"))

        sut.delete(nested)
        try await waitUntilGone(nested, in: sut)
        // The folders go after the file, inside the same queued deletion.
        await PendingFileDeletions.shared.waitUntilFinished(at: CloudDocumentController.canonicalPath(try #require(sut.storedLocation(of: nested))))

        #expect(!FileManager.default.fileExists(atPath: deep.path(percentEncoded: false)), "the emptied folder and its .DS_Store go")
        #expect(!FileManager.default.fileExists(atPath: deep.deletingLastPathComponent().path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: top.path(percentEncoded: false)), "a folder with another file stays")
        #expect(try text(of: sibling, in: sut) == "sibling")

        sut.delete(sibling)
        try await waitUntilGone(sibling, in: sut)
        await PendingFileDeletions.shared.waitUntilFinished(at: CloudDocumentController.canonicalPath(try #require(sut.storedLocation(of: sibling))))
        #expect(!FileManager.default.fileExists(atPath: top.path(percentEncoded: false)))
        #expect(FileManager.default.fileExists(atPath: sut.cloudDocumentController.moduleUrl.path(percentEncoded: false)), "the module folder stays")
    }

    @Test("A reference that names no file never deletes the module folder", arguments: [
        "/", "file:///Users/other/Documents/pdf"
    ])
    func folderReferenceDeletesNothing(path: String) async throws {
        let module = "FolderRefModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let kept = try await createFile("Kept-\(UUID().uuidString).test", text: "kept", module: module, with: sut)
        let hostile = FileUrl(fileId: UUID(), url: try #require(URL(string: path)), location: .newCloud, module: module, relativeUrl: nil)

        #expect(sut.storedLocation(of: hostile) == nil)
        await sut.removeStoredFile(hostile)
        await sut.deleteReplaced(hostile, keeping: kept)
        sut.delete(hostile)
        try await Task.sleep(for: .milliseconds(200))

        #expect(try text(of: kept, in: sut) == "kept")
    }

    @Test("The stored-file remover refuses a folder and a path outside the app's file roots")
    func removerRefusesFoldersAndForeignPaths() async throws {
        let module = "RefuseModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let kept = try await createFile("Sub/Kept-\(UUID().uuidString).test", text: "kept", module: module, with: sut)
        let folder = try #require(sut.storedLocation(of: kept)).deletingLastPathComponent()

        #expect(await sut.removeFileLoggingFailure(at: folder) == false)
        #expect(await sut.removeFileLoggingFailure(at: sut.cloudDocumentController.moduleUrl) == false)
        #expect(await sut.removeFileLoggingFailure(at: URL(filePath: "/etc/hosts")) == false)

        #expect(try text(of: kept, in: sut) == "kept")
        #expect(FileManager.default.fileExists(atPath: "/etc/hosts"))
    }

    // MARK: - CODE_AUDIT_21 §3.6

    @Test("An import of the same file right after its deletion keeps its file")
    func importAfterDeleteKeepsItsFile() async throws {
        let module = "ReimportModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let name = "Reused-\(UUID().uuidString).test"
        let bytes = Data("same".utf8)
        let deleted = try await createFile(name, text: "same", module: module, with: sut)

        sut.delete(deleted)
        // The same package comes in again while the deletion is still queued.
        var incoming = FileUrl(fileId: UUID(), url: rootUrl(named: name), location: .newCloud, module: module, relativeUrl: nil)
        incoming.resetData(bytes)
        let destination = try await sut.importDestination(for: incoming, contentHash: FileUrl.contentHash(of: bytes), referencedFileUrls: [])
        let imported = try #require(try await sut.createNewFileUrl(
            fileId: incoming.fileId,
            unconvertedFileUrl: destination,
            pathExtension: "test",
            requireDurableStorage: true
        ))
        try await Task.sleep(for: .milliseconds(300))

        #expect(try text(of: imported, in: sut) == "same")
    }

    @Test("An announced deletion holds an import back until the file is gone")
    func announcedDeletionHoldsImportBack() async throws {
        let module = "AnnounceModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let name = "Announced-\(UUID().uuidString).test"
        let bytes = Data("same".utf8)
        let file = try await createFile(name, text: "same", module: module, with: sut)
        var incoming = FileUrl(fileId: UUID(), url: rootUrl(named: name), location: .newCloud, module: module, relativeUrl: nil)
        incoming.resetData(bytes)
        let hash = FileUrl.contentHash(of: bytes)

        // The item left memory: its file is unreferenced, and still there.
        let announced = try #require(sut.announceDeletion(of: file))
        let importing = Task { [incoming] in
            let destination = try await sut.importDestination(for: incoming, contentHash: hash, referencedFileUrls: [])
            return (destination, FileManager.default.fileExists(atPath: sut.storedLocation(of: file)?.path(percentEncoded: false) ?? ""))
        }
        try await Task.sleep(for: .milliseconds(100))
        #expect(exists(file, in: sut))
        sut.delete(file, announced: announced)

        let (destination, fileWasThere) = try await importing.value
        #expect(!fileWasThere, "the import looked only after the deletion had run")
        #expect(destination.rawUrl == incoming.rawUrl)
    }

    @Test("A withdrawn deletion lets the import reuse the file")
    func withdrawnDeletionReleasesImport() async throws {
        let module = "WithdrawModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let name = "Kept-\(UUID().uuidString).test"
        let bytes = Data("same".utf8)
        let file = try await createFile(name, text: "same", module: module, with: sut)
        var incoming = FileUrl(fileId: UUID(), url: rootUrl(named: name), location: .newCloud, module: module, relativeUrl: nil)
        incoming.resetData(bytes)

        let announced = try #require(sut.announceDeletion(of: file))
        // Another item still uses the file.
        sut.delete(file, keepingStoredFile: true, announced: announced)
        let destination = try await sut.importDestination(for: incoming, contentHash: FileUrl.contentHash(of: bytes), referencedFileUrls: [])

        #expect(destination.rawUrl == incoming.rawUrl)
        #expect(try text(of: file, in: sut) == "same")
    }

    // MARK: - CODE_AUDIT_21 §3.7

    @Test("Staged bytes are written to their temp copy once per content")
    func stagedCopyIsWrittenOncePerContent() async throws {
        let module = "StagedModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        var staged = FileUrl(fileId: UUID(), url: rootUrl(named: "staged.test"), location: .other, module: module, relativeUrl: nil)
        staged.resetData(Data("first".utf8))

        let firstUrl = try #require(await sut.url(for: staged, action: { $0 }))
        #expect(try String(contentsOf: firstUrl, encoding: .utf8) == "first")
        // A second write would replace the copy and its date.
        let marker = Date(timeIntervalSince1970: 1_000_000)
        try FileManager.default.setAttributes([.modificationDate: marker], ofItemAtPath: firstUrl.path(percentEncoded: false))

        let againUrl = try #require(await sut.url(for: staged, action: { $0 }))
        #expect(againUrl == firstUrl)
        let modified = try FileManager.default.attributesOfItem(atPath: firstUrl.path(percentEncoded: false))[.modificationDate] as? Date
        #expect(modified == marker)

        staged.resetData(Data("second".utf8))
        let secondUrl = try #require(await sut.url(for: staged, action: { $0 }))
        #expect(secondUrl != firstUrl)
        #expect(try String(contentsOf: secondUrl, encoding: .utf8) == "second")
    }

    // MARK: - CODE_AUDIT_21 §5.2

    @Test("New bytes never take the name of another item's file")
    func writeDestinationAvoidsTakenName() async throws {
        let module = "WriteModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let name = "Goblin-\(UUID().uuidString).test"
        let first = try await createFile(name, text: "first goblin", module: module, with: sut)

        // A second item with the same name and no file yet.
        let destination = try await sut.writeDestination(for: rootUrl(named: name), replacing: nil, referencedFileUrls: [first])

        #expect(destination.lastPathComponent != name)
        let second = try await createFile(destination.lastPathComponent, text: "second goblin", module: module, with: sut)
        #expect(try text(of: first, in: sut) == "first goblin")
        #expect(try text(of: second, in: sut) == "second goblin")
        #expect(!sut.isSameStoredFile(first, second))
    }

    @Test("An item's own file is replaced in place unless another item shares it")
    func writeDestinationReplacesOwnFileInPlace() async throws {
        let module = "WriteModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let name = "Goblin-\(UUID().uuidString).test"
        let own = try await createFile(name, text: "goblin", module: module, with: sut)

        let inPlace = try await sut.writeDestination(for: rootUrl(named: name), replacing: own, referencedFileUrls: [])
        #expect(inPlace.lastPathComponent == name)

        let sharing = FileUrl(fileId: UUID(), url: own.rawUrl, location: .newCloud, module: module, relativeUrl: nil)
        let moved = try await sut.writeDestination(for: rootUrl(named: name), replacing: own, referencedFileUrls: [sharing])
        #expect(moved.lastPathComponent != name, "the other item keeps the shared file")
    }

    @Test("Deleting one of two items that share a file keeps the file")
    func deleteKeepsSharedFile() async throws {
        let module = "ShareModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let file = try await createFile("Shared-\(UUID().uuidString).test", text: "shared", module: module, with: sut)

        sut.delete(file, keepingStoredFile: true)
        try await Task.sleep(for: .milliseconds(200))

        #expect(try text(of: file, in: sut) == "shared")
    }

    @Test("copyFile copies the bytes to a new file and keeps the source")
    func copyFileCopiesAndKeepsSource() async throws {
        let module = "CopyModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let source = try await createFile("Goblin-\(UUID().uuidString).test", text: "goblin", module: module, with: sut)

        let copy = try #require(try await sut.copyFile(source, fileId: UUID(), to: rootUrl(named: "Goblin Copy-\(UUID().uuidString).test")))

        #expect(try text(of: copy, in: sut) == "goblin")
        #expect(try text(of: source, in: sut) == "goblin")
        #expect(copy.rawUrl != source.rawUrl)
    }

    @Test("copyFile never replaces another item's file of the same name")
    func copyFileKeepsExistingDestination() async throws {
        let module = "CopyModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let source = try await createFile("Goblin-\(UUID().uuidString).test", text: "goblin", module: module, with: sut)
        let existingName = "Goblin Copy-\(UUID().uuidString).test"
        let existing = try await createFile(existingName, text: "edited copy", module: module, with: sut)

        let copy = try #require(try await sut.copyFile(source, fileId: UUID(), to: rootUrl(named: existingName)))

        #expect(copy.rawUrl != existing.rawUrl, "the duplicate gets its own file name")
        #expect(try text(of: existing, in: sut) == "edited copy")
        #expect(try text(of: copy, in: sut) == "goblin")
    }

    @Test("Duplicating a file onto its own name keeps the file (rename-then-duplicate)")
    func copyOntoOwnNameKeepsFile() async throws {
        let module = "CopyModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let name = "Goblin Copy-\(UUID().uuidString).test"
        let source = try await createFile(name, text: "goblin", module: module, with: sut)

        let copy = try #require(try await sut.copyFile(source, fileId: UUID(), to: rootUrl(named: name)))

        #expect(exists(source, in: sut), "the source file must survive")
        #expect(try text(of: source, in: sut) == "goblin")
        #expect(copy.rawUrl != source.rawUrl)
        #expect(try text(of: copy, in: sut) == "goblin")
    }

    @Test("delete removes the real file and drops bytes held for it")
    func deleteRemovesRealFileAndHeldBytes() async throws {
        let module = "DeleteModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let file = try await createFile("Delete-\(UUID().uuidString).test", text: "real", module: module, with: sut)
        sut.holdPeerData(Data("from the master".utf8), for: file)
        #expect(sut.peerFiles.data(for: file.fileId) != nil)

        sut.delete(file)
        try await waitUntilGone(file, in: sut)

        #expect(!exists(file, in: sut), "the iCloud/Documents file itself is deleted, not a temp copy")
        #expect(sut.peerFiles.data(for: file.fileId) == nil)
    }

    @Test("copyFile reads the file on this device, not bytes a peer sent")
    func copyFileIgnoresHeldPeerBytes() async throws {
        let module = "CopyModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let source = try await createFile("Source-\(UUID().uuidString).test", text: "mine", module: module, with: sut)
        sut.holdPeerData(Data("master's version".utf8), for: source)

        let copy = try #require(try await sut.copyFile(source, fileId: UUID(), to: rootUrl(named: "Copy-\(UUID().uuidString).test")))

        #expect(try text(of: copy, in: sut) == "mine")
        sut.peerFiles.remove(source.fileId)
    }

    @Test("deleteReplaced keeps a file the replacement resolves to")
    func deleteReplacedKeepsSameLocation() async throws {
        let module = "ReplaceModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let file = try await createFile("Photo-\(UUID().uuidString).test", text: "photo", module: module, with: sut)
        let sameLocation = FileUrl(fileId: file.fileId, url: file.rawUrl, location: .newCloud, module: module, relativeUrl: nil)

        await sut.deleteReplaced(file, keeping: sameLocation)

        #expect(exists(file, in: sut), "the new reference points at this file")
        #expect(sut.isSameStoredFile(file, sameLocation))
    }

    @Test("deleteReplaced removes the old file when the replacement is elsewhere")
    func deleteReplacedRemovesOldFile() async throws {
        let module = "ReplaceModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let old = try await createFile("Old-\(UUID().uuidString).test", text: "old", module: module, with: sut)
        let new = try await createFile("New-\(UUID().uuidString).test", text: "new", module: module, with: sut)

        await sut.deleteReplaced(old, keeping: new)

        #expect(!exists(old, in: sut))
        #expect(exists(new, in: sut))
        #expect(!sut.isSameStoredFile(old, new))
    }

    // MARK: - Empty folders after a move or a replace

    private func folderExists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path(percentEncoded: false))
    }

    @Test("Moving the last file out of a folder removes the emptied folders, and only those")
    func moveRemovesEmptyFolders() async throws {
        let module = "MoveFoldersModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let id = UUID().uuidString
        let moving = try await createFile("From-\(id)/Mid/Moving.test", text: "moving", module: module, with: sut)
        let staying = try await createFile("From-\(id)/Staying.test", text: "staying", module: module, with: sut)
        let from = try #require(sut.storedLocation(of: staying)).deletingLastPathComponent()
        let mid = try #require(sut.storedLocation(of: moving)).deletingLastPathComponent()
        try Data().write(to: mid.appending(path: ".DS_Store"))

        let moved = try #require(try await sut.move(fileUrl: moving, to: "To-\(id)/Moved"))

        #expect(exists(moved, in: sut))
        #expect(try text(of: moved, in: sut) == "moving")
        #expect(!folderExists(mid), "the emptied folder goes with its .DS_Store")
        #expect(folderExists(from), "a folder that still holds a file stays")
        #expect(try text(of: staying, in: sut) == "staying")
        #expect(folderExists(sut.cloudDocumentController.moduleUrl))
    }

    @Test("Renaming a file inside its folder keeps the folder")
    func renameKeepsFolder() async throws {
        let module = "RenameFolderModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let id = UUID().uuidString
        let file = try await createFile("Same-\(id)/Old.test", text: "same", module: module, with: sut)
        let folder = try #require(sut.storedLocation(of: file)).deletingLastPathComponent()

        let renamed = try #require(try await sut.move(fileUrl: file, to: "Same-\(id)/New"))

        #expect(exists(renamed, in: sut))
        #expect(folderExists(folder))
    }

    @Test("Moving a file to another category removes the category folders it left empty")
    func categoryMoveRemovesEmptyFolders() async throws {
        let module = "CategoryMoveModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let id = UUID().uuidString
        let source = ItemListCategory.folder
        let file = try await createFile("\(source.title)/Sub-\(id)/Category.test", text: "category", module: module, with: sut)
        let sourceFolder = try #require(sut.storedLocation(of: file)).deletingLastPathComponent()

        let moved = try #require(await sut.move(fileUrl: file, from: source, to: .entry))

        #expect(exists(moved, in: sut))
        #expect(!folderExists(sourceFolder))
    }

    @Test("Replacing a file removes the folders the old file left empty")
    func replaceRemovesEmptyFolders() async throws {
        let module = "ReplaceFoldersModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let id = UUID().uuidString
        let old = try await createFile("Old-\(id)/Deep/Old.test", text: "old", module: module, with: sut)
        let kept = try await createFile("Old-\(id)/Kept.test", text: "kept", module: module, with: sut)
        let new = try await createFile("New-\(id)/New.test", text: "new", module: module, with: sut)
        let top = try #require(sut.storedLocation(of: kept)).deletingLastPathComponent()
        let deep = try #require(sut.storedLocation(of: old)).deletingLastPathComponent()

        await sut.deleteReplaced(old, keeping: new)

        #expect(!exists(old, in: sut))
        #expect(!folderExists(deep))
        #expect(folderExists(top), "a folder with another file stays")
        #expect(exists(new, in: sut))
    }

    @Test("Replacing with the file at the same location removes nothing")
    func replaceWithSameLocationKeepsFolders() async throws {
        let module = "ReplaceSameModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let file = try await createFile("Same-\(UUID().uuidString)/Deep/Same.test", text: "same", module: module, with: sut)
        let folder = try #require(sut.storedLocation(of: file)).deletingLastPathComponent()
        let sameLocation = FileUrl(fileId: file.fileId, url: file.rawUrl, location: .newCloud, module: module, relativeUrl: nil)

        await sut.deleteReplaced(file, keeping: sameLocation)

        #expect(exists(file, in: sut))
        #expect(folderExists(folder))
    }

    @Test("Removing an unused stored file removes the folders it left empty")
    func removeStoredFileRemovesEmptyFolders() async throws {
        let module = "StoredFoldersModule-\(UUID().uuidString)"
        let sut = await makeSut(module: module)
        let file = try await createFile("Unused-\(UUID().uuidString)/Deep/Unused.test", text: "unused", module: module, with: sut)
        let folder = try #require(sut.storedLocation(of: file)).deletingLastPathComponent()

        await sut.removeStoredFile(file)

        #expect(!exists(file, in: sut))
        #expect(!folderExists(folder))
        #expect(!folderExists(folder.deletingLastPathComponent()))
    }

    @Test("Releasing all held peer bytes empties the store")
    func removeAllEmptiesStore() {
        let store = PeerFileDataStore()
        let first = UUID()
        let second = UUID()
        store.hold(Data("one".utf8), for: first)
        store.hold(Data("two".utf8), for: second)

        store.removeAll()

        #expect(store.data(for: first) == nil)
        #expect(store.data(for: second) == nil)
    }

    @Test("The store evicts the oldest bytes once over its budget")
    func storeEvictsOldestOverBudget() {
        let store = PeerFileDataStore(maximumBytes: 10)
        let first = UUID()
        let second = UUID()
        let third = UUID()
        store.hold(Data(repeating: 1, count: 6), for: first)
        store.hold(Data(repeating: 2, count: 4), for: second)
        store.hold(Data(repeating: 3, count: 5), for: third)

        #expect(store.data(for: first) == nil, "the oldest entry made room")
        #expect(store.data(for: second) != nil)
        #expect(store.data(for: third) != nil)
    }

    @Test("A replaced hold gets a new generation, so a stale temp copy is never reused")
    func replacedHoldChangesGeneration() throws {
        let store = PeerFileDataStore()
        let file = UUID()
        store.hold(Data("old".utf8), for: file)
        let first = try #require(store.snapshot(for: file))

        store.hold(Data("new".utf8), for: file)
        let second = try #require(store.snapshot(for: file))

        #expect(first.generation != second.generation)
        #expect(second.data == Data("new".utf8))
        store.remove(file)
    }
}
