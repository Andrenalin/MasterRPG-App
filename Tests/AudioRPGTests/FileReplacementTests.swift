// @copyright André Trettin

import Foundation
import Testing

@testable import AudioRPG
@testable import CoreRPG

/// Replacing an item's file either deletes the file it had or leaves it on disk, and the user
/// is only asked when a stored file would be deleted.
@MainActor
@Suite("File replacement keeps or deletes the previous file")
struct FileReplacementTests {
    private func makeRoot() async throws -> AudioRootModel {
        let root = AudioRootModel.testRoot()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    /// Adds an item with a stored file holding `text`.
    private func addItem(text: String, in root: AudioRootModel) async throws -> (itemId: UUID, fileUrl: FileUrl) {
        let itemId = await root.itemController.addNew(type: .item)
        root.editController.reset(name: "Cue-\(UUID().uuidString)", itemId: itemId)
        try await root.editController.resetFile(data: Data(text.utf8), itemId: itemId, path: "")
        return (itemId, try fileUrl(of: itemId, in: root))
    }

    private func fileUrl(of itemId: UUID, in root: AudioRootModel) throws -> FileUrl {
        try #require(root.itemController.itemSync(for: itemId, noGame: true)?.fileUrl)
    }

    private func location(of fileUrl: FileUrl, in root: AudioRootModel) throws -> URL {
        try #require(root.editController.fileUrlDataController?.storedLocation(of: fileUrl))
    }

    private func text(of fileUrl: FileUrl, in root: AudioRootModel) throws -> String? {
        let url = try location(of: fileUrl, in: root)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return nil }
        return String(decoding: try Data(contentsOf: url), as: UTF8.self)
    }

    private func remove(_ fileUrls: FileUrl..., in root: AudioRootModel) {
        for fileUrl in fileUrls {
            guard let url = try? location(of: fileUrl, in: root) else { continue }
            try? FileManager.default.removeItem(at: url)
        }
    }

    /// A file outside the module folder, like one the file picker returns.
    private func pickedFile(text: String) throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "picked-\(UUID().uuidString).m4a")
        try Data(text.utf8).write(to: url)
        return url
    }

    // MARK: - New file from data (photo library, camera)

    @Test("Data written with .keep leaves the previous file and takes a new name")
    func dataKeepsPreviousFile() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)

        try await root.editController.resetFile(data: Data("new".utf8), itemId: itemId, path: "", replaced: .keep)

        let new = try fileUrl(of: itemId, in: root)
        defer { remove(old, new, in: root) }
        #expect(try location(of: new, in: root) != location(of: old, in: root))
        #expect(try text(of: old, in: root) == "old")
        #expect(try text(of: new, in: root) == "new")
    }

    @Test("Data written with .delete replaces the previous file")
    func dataDeletesPreviousFile() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)

        try await root.editController.resetFile(data: Data("new".utf8), itemId: itemId, path: "")

        let new = try fileUrl(of: itemId, in: root)
        defer { remove(old, new, in: root) }
        // Written over in place: the item's name did not change.
        #expect(try location(of: new, in: root) == location(of: old, in: root))
        #expect(try text(of: new, in: root) == "new")
    }

    // MARK: - New file from a url (picker, drop)

    @Test("A picked file with .keep leaves the previous file on disk")
    func urlKeepsPreviousFile() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)
        let picked = try pickedFile(text: "picked")
        defer { try? FileManager.default.removeItem(at: picked) }

        #expect(await root.editController.resetFile(url: picked, itemId: itemId, replaced: .keep))

        let new = try fileUrl(of: itemId, in: root)
        defer { remove(old, new, in: root) }
        #expect(try text(of: old, in: root) == "old")
        #expect(try text(of: new, in: root) == "picked")
    }

    @Test("A picked file with .delete removes the previous file")
    func urlDeletesPreviousFile() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)
        let picked = try pickedFile(text: "picked")
        defer { try? FileManager.default.removeItem(at: picked) }

        #expect(await root.editController.resetFile(url: picked, itemId: itemId))

        let new = try fileUrl(of: itemId, in: root)
        defer { remove(old, new, in: root) }
        #expect(try text(of: old, in: root) == nil)
        #expect(try text(of: new, in: root) == "picked")
    }

    // MARK: - When the user is asked

    @Test("Nothing would be deleted for an item without a file")
    func noFileNeedsNoDecision() async throws {
        let root = try await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)

        #expect(await root.editController.storedFileDeletedByReplacement(itemId: itemId) == nil)
    }

    @Test("The item's stored file would be deleted by another file")
    func storedFileNeedsDecision() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)
        defer { remove(old, in: root) }
        let picked = try pickedFile(text: "picked")
        defer { try? FileManager.default.removeItem(at: picked) }

        #expect(await root.editController.storedFileDeletedByReplacement(itemId: itemId) == old)
        #expect(await root.editController.storedFileDeletedByReplacement(itemId: itemId, url: picked) == old)
    }

    @Test("Picking the file the item already has deletes nothing")
    func sameFileNeedsNoDecision() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)
        defer { remove(old, in: root) }

        let same = try location(of: old, in: root)
        #expect(await root.editController.storedFileDeletedByReplacement(itemId: itemId, url: same) == nil)
    }

    @Test("A file another item uses is never deleted, so nothing is asked")
    func sharedFileNeedsNoDecision() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)
        defer { remove(old, in: root) }
        root.itemController.replace(model: AudioModel(id: UUID(), name: "Shares the file", fileUrl: old), isInsert: true)

        #expect(await root.editController.storedFileDeletedByReplacement(itemId: itemId) == nil)
    }

    @Test("A remote link has no stored file to decide about")
    func remoteLinkNeedsNoDecision() async throws {
        let root = try await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        let remote = FileUrl(fileId: itemId, url: try #require(URL(string: "https://example.com/cue.m4a")), location: .url, module: NetworkModules.audio.token, relativeUrl: nil)
        root.editController.reset(fileUrl: remote, itemId: itemId)

        #expect(await root.editController.storedFileDeletedByReplacement(itemId: itemId) == nil)
    }

    // MARK: - FileReplacementConfirmation

    /// Starts the question for `itemId` and returns once it is shown.
    private func ask(_ sut: FileReplacementConfirmation, itemId: UUID, in root: AudioRootModel) async throws -> (task: Task<ReplacedFileDisposal?, Never>, request: FileReplacementConfirmation.Request) {
        let task = Task { await sut.disposal(forReplacingFileOf: itemId, editControllable: root.editController) }
        for _ in 0..<200 where sut.request == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        return (task, try #require(sut.request))
    }

    @Test("Without a file to delete the replacement goes ahead unasked")
    func confirmationSkipsQuestion() async throws {
        let root = try await makeRoot()
        let itemId = await root.itemController.addNew(type: .item)
        let sut = FileReplacementConfirmation()

        #expect(await sut.disposal(forReplacingFileOf: itemId, editControllable: root.editController) == .delete)
        #expect(sut.request == nil)
    }

    @Test("The answer decides what happens to the previous file", arguments: [ReplacedFileDisposal.keep, .delete, nil])
    func confirmationReturnsAnswer(answer: ReplacedFileDisposal?) async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)
        defer { remove(old, in: root) }
        let sut = FileReplacementConfirmation()

        let (task, request) = try await ask(sut, itemId: itemId, in: root)
        #expect(request.fileName == old.rawUrl.lastPathComponent)
        sut.answer(request, with: answer)

        #expect(await task.value == answer)
        #expect(sut.request == nil)
    }

    @Test("An answer still counts after the alert's binding was cleared")
    func confirmationAnswersAfterDismissal() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)
        defer { remove(old, in: root) }
        let sut = FileReplacementConfirmation()

        let (task, request) = try await ask(sut, itemId: itemId, in: root)
        sut.dismissed()
        sut.answer(request, with: .keep)

        #expect(await task.value == .keep)
    }

    @Test("A question whose view went away is cancelled")
    func confirmationCancelsWithItsView() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)
        defer { remove(old, in: root) }
        let sut = FileReplacementConfirmation()

        let (task, _) = try await ask(sut, itemId: itemId, in: root)
        sut.cancel()

        #expect(await task.value == nil)
        #expect(sut.request == nil)
    }

    @Test("A cancelled replacement leaves the item and its file alone")
    func cancelledReplacementKeepsItem() async throws {
        let root = try await makeRoot()
        let (itemId, old) = try await addItem(text: "old", in: root)
        defer { remove(old, in: root) }
        let picked = try pickedFile(text: "picked")
        defer { try? FileManager.default.removeItem(at: picked) }
        let sut = FileReplacementConfirmation()

        let replacement = Task { await sut.resetFile(url: picked, itemId: itemId, editControllable: root.editController) }
        for _ in 0..<200 where sut.request == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        sut.answer(try #require(sut.request), with: nil)

        #expect(await replacement.value == false)
        #expect(try fileUrl(of: itemId, in: root) == old)
        #expect(try text(of: old, in: root) == "old")
    }
}
