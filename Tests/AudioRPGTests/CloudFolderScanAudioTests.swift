// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import AudioRPG
@testable import CoreRPG

/// The iCloud sync of the Audio module for a folder that exists in iCloud but not in the app:
/// a game master put new audio files into `Audio Text Roman`.
// Serialized: the sync takes the process-wide data-mutation lock, and a parallel one is refused.
@Suite(.serialized)
@MainActor
struct CloudFolderScanAudioTests {
    private let folderName = "Audio Text Roman"
    private let module = NetworkModules.audio.token

    private func writeFiles(_ names: [String], in folder: String, below moduleUrl: URL) throws -> URL {
        let folderUrl = moduleUrl.appending(path: folder, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folderUrl, withIntermediateDirectories: true)
        for name in names {
            try Data(name.utf8).write(to: folderUrl.appending(path: name))
        }
        return folderUrl
    }

    private func scannedPlan(_ controller: CloudScanController) async throws -> CloudScanPlan {
        guard case .plan(let plan) = try #require(await controller.scan()) else {
            Issue.record("the module folder should be readable")
            return CloudScanPlan()
        }
        return plan
    }

    @Test("Audio files in an iCloud folder the app does not have get the folder and an item each")
    func newFolderWithNewAudioFiles() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()
        let files = try #require(root.itemController.fileUrlDataController)
        let folderUrl = try writeFiles(["Kapitel 1.mp3", "Kapitel 2.m4a", "Kapitel 3.wav"], in: folderName, below: files.cloudDocumentController.moduleUrl)
        defer { try? FileManager.default.removeItem(at: folderUrl) }
        let controller = CloudScanController(itemController: root.itemController, editController: root.editController)

        var plan = try await scannedPlan(controller)
        plan.items.removeAll { $0.file.components.first != folderName }
        plan.folders.removeAll { $0.path.first != folderName }
        #expect(plan.folders.map(\.name) == [folderName])
        #expect(plan.items.map(\.name).sorted() == ["Kapitel 1", "Kapitel 2", "Kapitel 3"])

        #expect(await controller.apply(plan) == .synced(added: 3, folders: 1, moved: 0, trashed: 0))
        let folderId = CloudFolderScan.derivedId(module: module, path: [folderName], isFolder: true)
        let folder = try #require(root.itemController.itemSync(for: folderId, noGame: true))
        #expect(folder.isFolder)
        #expect(folder.entries.count == 3)
    }

    @Test("An audio item at the root whose file is in an iCloud folder is offered to move into a new folder")
    func rootItemMovesIntoNewFolder() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()
        let files = try #require(root.itemController.fileUrlDataController)
        let folderUrl = try writeFiles(["Kapitel 1.mp3", "Kapitel 2.mp3"], in: folderName, below: files.cloudDocumentController.moduleUrl)
        defer { try? FileManager.default.removeItem(at: folderUrl) }

        // Items the app already has, at the root, that point at the files in the folder.
        var itemIds: [UUID] = []
        for name in ["Kapitel 1", "Kapitel 2"] {
            let file = CloudScanFile(components: [folderName, "\(name).mp3"])
            let id = CloudFolderScan.derivedId(module: module, path: file.components, isFolder: false)
            let seed = CloudScanPlan(items: [.init(id: id, name: name, parentId: nil, file: file)])
            _ = root.itemController.insertCloudScan(seed)
            itemIds.append(id)
        }
        let controller = CloudScanController(itemController: root.itemController, editController: root.editController)

        var plan = try await scannedPlan(controller)
        plan.moves.removeAll { !itemIds.contains($0.id) }
        plan.items.removeAll()  // the module folder may hold other files than this test's
        plan.folders.removeAll { $0.path.first != folderName }
        #expect(plan.moves.count == 2, "both items are offered to move")
        #expect(plan.folders.map(\.name) == [folderName])

        #expect(await controller.apply(plan) == .synced(added: 0, folders: 1, moved: 2, trashed: 0))
        let folderId = CloudFolderScan.derivedId(module: module, path: [folderName], isFolder: true)
        for id in itemIds {
            #expect(root.itemController.itemSync(for: id, noGame: true)?.parentId == folderId)
        }
    }

    @Test("Items sent by a game master keep the id of a folder this app lacks and move into a new folder")
    func itemsWithMissingParentMoveIntoNewFolder() async throws {
        let root = AudioRootModel.testRoot()
        await root.itemController.resetData()
        let files = try #require(root.itemController.fileUrlDataController)
        let folderUrl = try writeFiles(["Kapitel 1.mp3", "Kapitel 2.mp3"], in: folderName, below: files.cloudDocumentController.moduleUrl)
        defer { try? FileManager.default.removeItem(at: folderUrl) }

        // The master's folder is not part of what was sent, so the parent id points at nothing.
        let mastersFolderId = UUID()
        var itemIds: [UUID] = []
        for name in ["Kapitel 1", "Kapitel 2"] {
            let file = CloudScanFile(components: [folderName, "\(name).mp3"])
            let id = CloudFolderScan.derivedId(module: module, path: file.components, isFolder: false)
            _ = root.itemController.insertCloudScan(CloudScanPlan(items: [.init(id: id, name: name, parentId: mastersFolderId, file: file)]))
            itemIds.append(id)
        }
        #expect(root.itemController.itemSync(for: mastersFolderId, noGame: true) == nil)
        let controller = CloudScanController(itemController: root.itemController, editController: root.editController)

        var plan = try await scannedPlan(controller)
        plan.items.removeAll()  // the module folder may hold other files than this test's
        plan.moves.removeAll { !itemIds.contains($0.id) }
        plan.folders.removeAll { $0.path.first != folderName }
        #expect(plan.moves.count == 2, "the sync offers to move them, instead of saying everything is in sync")
        #expect(plan.folders.map(\.name) == [folderName])

        #expect(await controller.apply(plan) == .synced(added: 0, folders: 1, moved: 2, trashed: 0))
        let folderId = CloudFolderScan.derivedId(module: module, path: [folderName], isFolder: true)
        let folder = try #require(root.itemController.itemSync(for: folderId, noGame: true))
        #expect(Set(folder.entries.map(\.childId)) == Set(itemIds), "the folder lists them")
        for id in itemIds {
            #expect(root.itemController.itemSync(for: id, noGame: true)?.parentId == folderId)
        }
    }
}
#endif
