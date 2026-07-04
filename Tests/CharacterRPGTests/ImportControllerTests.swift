// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import RPGResourcesDebug
import Testing

@testable import CharacterRPG

@MainActor
struct ImportControllerTests {
    @Test func importing() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        
        let sut = await root.importController

        let bundle = ResourcesDebug.bundle
        let url = bundle.url(forResource: ResourcesDebug.valueTestData, withExtension: "gmz").unsafelyUnwrapped

        let task = sut.importUrl(from: url)
        let _ = try await task.value
        #expect(await root.itemController.itemDataModel.items.count == 15)
    }
    
    @Test func importingItemInFolderWithExcludesSiblings() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.importController

        let exportController = await root.exportController
        let edit = await root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let itemId = await root.itemController.addNew(type: .item)
        let siblingId = await root.itemController.addNew(type: .item)
        await edit.addItem(itemId: itemId, parentId: folderId)
        await edit.addItem(itemId: siblingId, parentId: folderId)

        let ids = await exportController.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .value))
        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }

        _ = try await exportController.export(itemIds: ids, into: stream)

        let data = stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data
        try #require(data != nil)

        await edit.delete(itemId: folderId)
        await root.itemController.delete(itemId: folderId)
        await edit.delete(itemId: itemId)
        await root.itemController.delete(itemId: itemId)
        await edit.delete(itemId: siblingId)
        await root.itemController.delete(itemId: siblingId)

        #expect(await root.itemController.itemDataModel.items.contains(itemId) == false)
        #expect(await root.itemController.itemDataModel.items.contains(folderId) == false)
        #expect(await root.itemController.itemDataModel.items.contains(siblingId) == false)

        let importStream = InputStream(data: data!)
        importStream.open()
        defer { importStream.close() }

        try await sut.importStream(from: importStream, forceSave: false)

        #expect(await root.itemController.itemDataModel.items.contains(itemId))
        #expect(await root.itemController.itemDataModel.items.contains(folderId))
        #expect(await root.itemController.itemDataModel.items.contains(siblingId) == false)
    }

    @Test func importingPreservesNestedFolderHierarchy() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.importController
        let exportController = await root.exportController
        let edit = await root.editController

        // Setup: folder1 → folder2 → character1, no siblings at either level
        let folder1 = await edit.addNew(type: .folder)
        try #require(folder1 != nil)
        let folder2 = await edit.addNew(type: .folder)
        try #require(folder2 != nil)
        let folder1Id = folder1!.id
        let folder2Id = folder2!.id
        let character1Id = await root.itemController.addNew(type: .item)
        await edit.addItem(itemId: character1Id, parentId: folder2Id)
        await edit.addItem(itemId: folder2Id, parentId: folder1Id)

        // No siblings → folder2 and folder1 are fully promoted into ids, not partial
        let ids = await exportController.exporting(itemIds: ItemModuleIds(ids: Set([character1Id]), module: .value))
        #expect(ids.ids[.value]?.contains(character1Id) == true)
        #expect(ids.ids[.value]?.contains(folder2Id) == true)
        #expect(ids.ids[.value]?.contains(folder1Id) == true)
        #expect(ids.partialIds[.value] == nil)

        let stream = OutputStream.toMemory()
        stream.open()
        defer { stream.close() }
        _ = try await exportController.export(itemIds: ids, into: stream)
        let data = try #require(stream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)

        await edit.delete(itemId: character1Id)
        await root.itemController.delete(itemId: character1Id)
        await edit.delete(itemId: folder2Id)
        await root.itemController.delete(itemId: folder2Id)
        await edit.delete(itemId: folder1Id)
        await root.itemController.delete(itemId: folder1Id)

        #expect(await root.itemController.itemDataModel.items.contains(character1Id) == false)
        #expect(await root.itemController.itemDataModel.items.contains(folder2Id) == false)
        #expect(await root.itemController.itemDataModel.items.contains(folder1Id) == false)

        let importStream = InputStream(data: data)
        importStream.open()
        defer { importStream.close() }
        try await sut.importStream(from: importStream, forceSave: false)

        #expect(await root.itemController.itemDataModel.items.contains(character1Id))
        #expect(await root.itemController.itemDataModel.items.contains(folder2Id))
        #expect(await root.itemController.itemDataModel.items.contains(folder1Id))
        let importedCharacter = await root.itemController.item(for: character1Id)
        #expect(importedCharacter?.parentId == folder2Id)
    }

    @Test func importingSecondCharacterMergesIntoExistingFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.importController
        let exportController = await root.exportController
        let edit = await root.editController

        // Setup: folder1 → folder2 → [character1, character2]
        let folder1 = await edit.addNew(type: .folder)
        try #require(folder1 != nil)
        let folder2 = await edit.addNew(type: .folder)
        try #require(folder2 != nil)
        let folder1Id = folder1!.id
        let folder2Id = folder2!.id
        let character1Id = await root.itemController.addNew(type: .item)
        let character2Id = await root.itemController.addNew(type: .item)
        await edit.addItem(itemId: character1Id, parentId: folder2Id)
        await edit.addItem(itemId: character2Id, parentId: folder2Id)
        await edit.addItem(itemId: folder2Id, parentId: folder1Id)

        // Export character1 only — folder2/folder1 are partial since character2 is an unexported sibling
        let ids1 = await exportController.exporting(itemIds: ItemModuleIds(ids: Set([character1Id]), module: .value))
        #expect(ids1.partialIds[.value]?.contains(folder2Id) == true)
        let stream1 = OutputStream.toMemory()
        stream1.open()
        _ = try await exportController.export(itemIds: ids1, into: stream1)
        let data1 = try #require(stream1.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)
        stream1.close()

        // Export character2 only — same partial folder pattern
        let ids2 = await exportController.exporting(itemIds: ItemModuleIds(ids: Set([character2Id]), module: .value))
        let stream2 = OutputStream.toMemory()
        stream2.open()
        _ = try await exportController.export(itemIds: ids2, into: stream2)
        let data2 = try #require(stream2.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)
        stream2.close()

        await edit.delete(itemId: character1Id)
        await root.itemController.delete(itemId: character1Id)
        await edit.delete(itemId: character2Id)
        await root.itemController.delete(itemId: character2Id)
        await edit.delete(itemId: folder2Id)
        await root.itemController.delete(itemId: folder2Id)
        await edit.delete(itemId: folder1Id)
        await root.itemController.delete(itemId: folder1Id)

        // First import: establishes folder1/folder2/character1
        let importStream1 = InputStream(data: data1)
        importStream1.open()
        try await sut.importStream(from: importStream1, forceSave: false)
        importStream1.close()
        #expect(await root.itemController.itemDataModel.items.contains(character1Id))
        #expect(await root.itemController.itemDataModel.items.contains(folder2Id))
        #expect(await root.itemController.itemDataModel.items.contains(character2Id) == false)

        // Second import: folder2 already exists — merge adds character2 alongside character1
        let importStream2 = InputStream(data: data2)
        importStream2.open()
        defer { importStream2.close() }
        try await sut.importStream(from: importStream2, forceSave: false)

        #expect(await root.itemController.itemDataModel.items.contains(character1Id))
        #expect(await root.itemController.itemDataModel.items.contains(character2Id))
        let folder2Item = await root.itemController.item(for: folder2Id)
        let folder2Children = folder2Item?.entries.map(\.childId) ?? []
        #expect(folder2Children.contains(character1Id))
        #expect(folder2Children.contains(character2Id))
    }

    @Test func importingTwoCharactersIntoSameFolderMergesBoth() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.importController
        let exportController = await root.exportController
        let edit = await root.editController

        // Setup: folder1 → [character1, character2]
        let folder1 = await edit.addNew(type: .folder)
        try #require(folder1 != nil)
        let folder1Id = folder1!.id
        let character1Id = await root.itemController.addNew(type: .item)
        let character2Id = await root.itemController.addNew(type: .item)
        await edit.addItem(itemId: character1Id, parentId: folder1Id)
        await edit.addItem(itemId: character2Id, parentId: folder1Id)

        // Export character1 only — folder1 is partial since character2 is an unexported sibling
        let ids1 = await exportController.exporting(itemIds: ItemModuleIds(ids: Set([character1Id]), module: .value))
        #expect(ids1.partialIds[.value]?.contains(folder1Id) == true)
        let stream1 = OutputStream.toMemory()
        stream1.open()
        _ = try await exportController.export(itemIds: ids1, into: stream1)
        let data1 = try #require(stream1.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)
        stream1.close()

        // Export character2 only — same partial pattern
        let ids2 = await exportController.exporting(itemIds: ItemModuleIds(ids: Set([character2Id]), module: .value))
        let stream2 = OutputStream.toMemory()
        stream2.open()
        _ = try await exportController.export(itemIds: ids2, into: stream2)
        let data2 = try #require(stream2.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)
        stream2.close()

        await edit.delete(itemId: character1Id)
        await root.itemController.delete(itemId: character1Id)
        await edit.delete(itemId: character2Id)
        await root.itemController.delete(itemId: character2Id)
        await edit.delete(itemId: folder1Id)
        await root.itemController.delete(itemId: folder1Id)

        // First import: establishes folder1/character1
        let importStream1 = InputStream(data: data1)
        importStream1.open()
        try await sut.importStream(from: importStream1, forceSave: false)
        importStream1.close()
        #expect(await root.itemController.itemDataModel.items.contains(character1Id))
        #expect(await root.itemController.itemDataModel.items.contains(folder1Id))
        #expect(await root.itemController.itemDataModel.items.contains(character2Id) == false)

        // Second import: folder1 already exists — merge adds character2 alongside character1
        let importStream2 = InputStream(data: data2)
        importStream2.open()
        defer { importStream2.close() }
        try await sut.importStream(from: importStream2, forceSave: false)

        #expect(await root.itemController.itemDataModel.items.contains(character1Id))
        #expect(await root.itemController.itemDataModel.items.contains(character2Id))
        let folder1Item = await root.itemController.item(for: folder1Id)
        let folder1Children = folder1Item?.entries.map(\.childId) ?? []
        #expect(folder1Children.contains(character1Id))
        #expect(folder1Children.contains(character2Id))
    }

    @Test func importingDoesNotOverwriteParentIdWithNilOnMerge() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = await root.importController
        let exportController = await root.exportController
        let edit = await root.editController

        // Create character1 at root — parentId is nil at this point
        let character1Id = await root.itemController.addNew(type: .item)

        // Export character1 standalone — the serialised data carries parentId = nil
        let standaloneIds = await exportController.exporting(itemIds: ItemModuleIds(ids: Set([character1Id]), module: .value))
        let standaloneStream = OutputStream.toMemory()
        standaloneStream.open()
        _ = try await exportController.export(itemIds: standaloneIds, into: standaloneStream)
        let standaloneData = try #require(standaloneStream.property(forKey: Stream.PropertyKey.dataWrittenToMemoryStreamKey) as? Data)
        standaloneStream.close()

        // Move character1 into folder2
        let folder2 = await edit.addNew(type: .folder)
        try #require(folder2 != nil)
        let folder2Id = folder2!.id
        await edit.addItem(itemId: character1Id, parentId: folder2Id)

        // Precondition: character1 is now inside folder2
        let characterBefore = await root.itemController.item(for: character1Id)
        try #require(characterBefore?.parentId == folder2Id)

        // Import the old standalone data (parentId = nil) — merge must not overwrite folder2Id
        let importStream = InputStream(data: standaloneData)
        importStream.open()
        defer { importStream.close() }
        try await sut.importStream(from: importStream, forceSave: false)

        let characterAfter = await root.itemController.item(for: character1Id)
        #expect(characterAfter?.parentId == folder2Id)
    }
}
