// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import AudioRPG

@MainActor
struct SheetControllerTests {
    @Test func audioSheetBasic() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.isShown == true)
        #expect(model.level == 0)
        #expect(model.sheetType == SheetModelType.item)
        #expect(model.source.itemId == itemId)
        #expect(model.canAdd == false)
        #expect(model.showHeader == false)
    }

    @Test func audioSheetWithAudioInline() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)
        let item = root.itemController.itemOrEmpty(for: itemId!)

        let rootManager = RootManager(anyRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        if item.hasAudio {
            let audioInline = model.entries.first(where: { $0.sheetType == SheetModelType.audio })
            #expect(audioInline != nil)
        }
    }

    @Test func audioSheetEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)

        #expect(model.entries.count >= 0)
        for entry in model.entries {
            if entry.sheetType == SheetModelType.audio {
                #expect(entry.level == 0)
            }
        }
    }

    @Test func audioSheetTrackEntries() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let entries = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

        for entry in entries {
            #expect(entry.sheetType == SheetModelType.audio)
        }
    }

    @Test func audioSheetWithLinks() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let entries = sut.sheetEntries(root: rootManager, itemId: itemId!, level: 0, moduleDepth: 0, isEditor: false)

        for entry in entries {
            for linkedSheet in entry.entries {
                #expect(linkedSheet.isShown == false)
                #expect(linkedSheet.level == 1)
            }
        }
    }

    @Test func audioSheetIsShownPropagation() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let modelShown = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, isEditor: false)
        #expect(modelShown.isShown == true)

        let modelHidden = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: false, isEditor: false)
        #expect(modelHidden.isShown == false)
    }

    @Test func audioSheetLevelLimit() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        // Test isFolded at moduleDepth >= 1
        let modelFolded = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 1, isEditor: false)
        #expect(modelFolded.isFolded == true)
        #expect(modelFolded.entries.isEmpty)

        let modelNotFolded = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 0, isShown: true, moduleDepth: 0, isEditor: false)
        #expect(modelNotFolded.isFolded == false)

        // Test isFolded in editor mode at level > 0
        let modelFoldedEditor = sut.sheet(root: rootManager, itemId: itemId!, destination: nil, level: 1, isShown: true, moduleDepth: 0, isEditor: true)
        #expect(modelFoldedEditor.isFolded == true)
        #expect(modelFoldedEditor.entries.isEmpty)
    }

    @Test func audioSheetDestination() async throws {
        let root = try await MockRoot.importTestData()

        let sut = SheetController(itemController: root.itemController)
        let itemId = root.itemController.itemDataModel.items.first
        try #require(itemId != nil)

        let rootManager = RootManager(anyRoot: root)

        let destination = ItemRowModel(itemId: Foundation.UUID(), typeId: NetworkModules.map)
        let model = sut.sheet(root: rootManager, itemId: itemId!, destination: destination, level: 1, isShown: false, isEditor: false)

        #expect(model.destination.itemId == destination.itemId)
    }

    @Test func audioUpdateRefreshesInlineTrackEntriesAndRemovesDeletedEntries() async throws {
        let root = try await MockRoot.importTestData()
        let rootManager = RootManager(anyRoot: root)
        let sut = SheetController(itemController: root.itemController)
        let itemId = UUID()
        let keptTrackId = UUID()
        let removedTrackId = UUID()
        let newTrackId = UUID()
        let originalFileUrl = FileUrl(fileId: itemId, url: URL(filePath: "/tmp/original.m4a"), location: .local, module: "audio", relativeUrl: nil)
        let updatedFileUrl = FileUrl(fileId: itemId, url: URL(filePath: "/tmp/updated.m4a"), location: .local, module: "audio", relativeUrl: nil)
        let keptEntry = AudioEntryModel(id: UUID(), audioId: keptTrackId)
        let removedEntry = AudioEntryModel(id: UUID(), audioId: removedTrackId)

        root.itemController.replace(
            model: AudioModel(
                id: keptTrackId,
                name: "Old Track",
                description: "Old track description",
                fileUrl: originalFileUrl
            ),
            isInsert: true
        )
        root.itemController.replace(
            model: AudioModel(
                id: removedTrackId,
                name: "Removed Track",
                description: "Removed track description",
                fileUrl: originalFileUrl
            ),
            isInsert: true
        )
        root.itemController.replace(
            model: AudioModel(
                id: itemId,
                name: "Old Playlist",
                description: "Old playlist description",
                fileUrl: originalFileUrl,
                entries: [keptEntry, removedEntry]
            ),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, isEditor: false)

        let newEntry = AudioEntryModel(id: UUID(), audioId: newTrackId)
        root.itemController.itemOrEmpty(for: keptTrackId).name = "Updated Track"
        root.itemController.itemOrEmpty(for: keptTrackId).description = "Updated track description"
        root.itemController.replace(
            model: AudioModel(
                id: newTrackId,
                name: "New Track",
                description: "New track description",
                fileUrl: updatedFileUrl
            ),
            isInsert: true
        )
        let item = root.itemController.itemOrEmpty(for: itemId)
        item.name = "Updated Playlist"
        item.description = "Updated playlist description"
        item.fileUrl = updatedFileUrl
        item.entries = [keptEntry, newEntry]

        sut.update(root: rootManager, sheetModel: sheetModel, isEditor: false)

        #expect(sheetModel.name == "Updated Playlist")
        #expect(sheetModel.inlineEntries.first?.name == "Updated Playlist")
        #expect(sheetModel.inlineEntries.first?.description == "Updated playlist description")
        #expect(sheetModel.entries.map(\.source.entryId).contains(keptEntry.id))
        #expect(!sheetModel.entries.map(\.source.entryId).contains(removedEntry.id))
        #expect(sheetModel.entries.map(\.source.entryId).contains(newEntry.id))
        #expect(sheetModel.entries.first { $0.source.entryId == keptEntry.id }?.name == "Updated Track")
        #expect(sheetModel.entries.first { $0.source.entryId == keptEntry.id }?.description == "Updated track description")
    }

    @Test func audioUpdateLeavesFoldedEntriesCollapsed() async throws {
        let root = try await MockRoot.importTestData()
        let rootManager = RootManager(anyRoot: root)
        let sut = SheetController(itemController: root.itemController)
        let itemId = UUID()
        let trackId = UUID()

        root.itemController.replace(
            model: AudioModel(
                id: trackId,
                name: "Folded Track",
                description: "Folded track description",
                fileUrl: FileUrl(fileId: trackId, url: URL(filePath: "/tmp/track.m4a"), location: .local, module: "audio", relativeUrl: nil)
            ),
            isInsert: true
        )
        root.itemController.replace(
            model: AudioModel(
                id: itemId,
                name: "Folded Playlist",
                description: "Folded playlist description",
                entries: [AudioEntryModel(id: UUID(), audioId: trackId)]
            ),
            isInsert: true
        )

        let sheetModel = sut.sheet(root: rootManager, itemId: itemId, destination: nil, level: 0, isShown: true, moduleDepth: 1, isEditor: false)
        root.itemController.itemOrEmpty(for: itemId).name = "Folded Updated"

        sut.update(root: rootManager, sheetModel: sheetModel, isEditor: false)

        #expect(sheetModel.name == "Folded Updated")
        #expect(sheetModel.isFolded)
        #expect(sheetModel.entries.isEmpty)
    }
}
