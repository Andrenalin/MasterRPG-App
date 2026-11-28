// @copyright André Trettin

import CoreRPG
import Foundation
import DiceRPG
import PdfRPG
import PhotoRPG
import RPGResourcesDebug
import TableRPG
import Testing

@testable import CharacterRPG

@MainActor
struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = try await MockRoot.importTestData()
        let sut = root.exportController

        var ids = sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.count == 15)

        let itemId = await root.itemController.addNew(type: .item)
        ids = sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.contains(itemId))

        let newId = await root.itemController.addNew(type: .item)
        let entry = ValueEntryModel(id: UUID(), name: "Nothing", type: .text, value: root.linkController.generateLink(itemId: newId))
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        ids = sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.count == 17)
    }

    @Test func exportingAllAfterDeletion() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController
        let edit = root.editController

        let item = await edit.addNew(type: .item)
        let deleted = await edit.addNew(type: .item)
        try #require(item != nil)
        try #require(deleted != nil)
        edit.reset(name: "keep", itemId: item!.id, forceSave: false)
        edit.reset(name: "delete", itemId: deleted!.id, forceSave: false)

        await edit.delete(itemId: deleted!.id)

        let ids = sut.exportingAll()
        try #require(ids.ids[.value] != nil)
        #expect(ids.ids[.value]!.contains(item!.id))
        #expect(!ids.ids[.value]!.contains(deleted!.id))
        #expect(ids.ids[.value]!.count == 1)
    }

    @Test func exportingItemInFolderIncludesFolder() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController
        let edit = root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let itemId = await root.itemController.addNew(type: .item)
        edit.addItem(itemId: itemId, parentId: folderId)

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .value))
        let valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(itemId))
        #expect(valueIds!.contains(folderId))
        #expect(ids.partialIds[.value] == nil)
    }

    @Test func exportingItemInFolderExcludesSiblings() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController
        let edit = root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let itemId = await root.itemController.addNew(type: .item)
        let siblingId = await root.itemController.addNew(type: .item)
        edit.addItem(itemId: itemId, parentId: folderId)
        edit.addItem(itemId: siblingId, parentId: folderId)

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .value))
        let valueIds = ids.ids[.value]
        let partialIds = ids.partialIds[.value]
        try #require(valueIds != nil)
        try #require(partialIds != nil)
        #expect(valueIds!.contains(itemId))
        #expect(!valueIds!.contains(folderId))
        #expect(ids.partialIds[.value]?.contains(folderId) == true)
        #expect(!valueIds!.contains(siblingId))
    }

    @Test func exportingItemInFolderInlcudeSiblingsIfFolderIsExported() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController
        let edit = root.editController

        let folder = await edit.addNew(type: .folder)
        try #require(folder != nil)
        let folderId = folder!.id

        let otherItemId = await root.itemController.addNew(type: .item)
        let itemId = await root.itemController.addNew(type: .item)
        let siblingId = await root.itemController.addNew(type: .item)
        edit.addItem(itemId: itemId, parentId: folderId)
        edit.addItem(itemId: siblingId, parentId: folderId)

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId, folderId]), module: .value))
        let valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(itemId))
        #expect(valueIds!.contains(folderId))
        #expect(valueIds!.contains(siblingId))
        #expect(ids.partialIds[.value] == nil)
        #expect(!valueIds!.contains(otherItemId))
    }

    @Test func exportingItemInNestedFolderIncludesFoldersRecursively() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController
        let edit = root.editController

        let outerFolder = await edit.addNew(type: .folder)
        let innerFolder = await edit.addNew(type: .folder)
        try #require(outerFolder != nil)
        try #require(innerFolder != nil)
        let outerFolderId = outerFolder!.id
        let innerFolderId = innerFolder!.id

        let itemId = await root.itemController.addNew(type: .item)
        let siblingId = await root.itemController.addNew(type: .item)
        edit.addItem(itemId: itemId, parentId: innerFolderId)
        edit.addItem(itemId: innerFolderId, parentId: outerFolderId)
        edit.addItem(itemId: siblingId, parentId: outerFolderId)

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .value))
        let valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(itemId))
        // innerFolder: its only child (item) is exported → all children in results → promoted to ids
        #expect(valueIds!.contains(innerFolderId))
        // outerFolder: sibling is not exported → not all children in results → partial only
        #expect(!valueIds!.contains(outerFolderId))
        #expect(ids.partialIds[.value]?.contains(outerFolderId) == true)
        #expect(!valueIds!.contains(siblingId))
    }

    @Test func exportingCharacterIncludesEntryValueIdChild() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        let characterId = await root.itemController.addNew(type: .item)
        let childId = await root.itemController.addNew(type: .item)
        root.itemController.itemOrEmpty(for: characterId).entries.append(
            ValueEntryModel.fixture(valueId: childId)
        )

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([characterId]), module: .value))
        let valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(characterId))
        #expect(valueIds!.contains(childId))
    }

    @Test func exportingCharacterIncludesTransitiveEntryValueIdChildren() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        let characterId = await root.itemController.addNew(type: .character)
        let childId = await root.itemController.addNew(type: .item)
        let grandchildId = await root.itemController.addNew(type: .item)
        root.itemController.itemOrEmpty(for: characterId).entries.append(
            ValueEntryModel.fixture(valueId: childId)
        )
        root.itemController.itemOrEmpty(for: childId).entries.append(
            ValueEntryModel.fixture(valueId: grandchildId)
        )

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([characterId]), module: .value))
        let valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(characterId))
        #expect(valueIds!.contains(childId))
        #expect(valueIds!.contains(grandchildId))
    }

    @Test func exportingCharacterWithEntryDiceIdExportsDice() async throws {
        let root = try await MockRoot.importTestData()

        let sut = root.exportController
        let diceId = try #require(root.diceRoot.exportControllable.exportingAll().ids[.dice]?.first)

        let characterId = await root.itemController.addNew(type: .item)
        root.itemController.itemOrEmpty(for: characterId).entries.append(
            ValueEntryModel.fixture(diceId: diceId)
        )

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([characterId]), module: .value))
        let valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(characterId))
        #expect(ids.ids[.dice]?.contains(diceId) == true)
    }

    @Test func exportingCharacterWithPhotoIdExportsPhoto() async throws {
        let root = try await MockRoot.importTestData()

        let sut = root.exportController
        let photoId = try #require(root.photoRoot.exportControllable.exportingAll().ids[.photo]?.first)

        let characterId = await root.itemController.addNew(type: .item)
        root.itemController.itemOrEmpty(for: characterId).photoId = photoId

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([characterId]), module: .value))
        let valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(characterId))
        #expect(ids.ids[.photo]?.contains(photoId) == true)
    }

    @Test func exportingCharacterWithEntryTextLinksExportsCrossModuleItems() async throws {
        let root = try await MockRoot.importTestData()

        let sut = root.exportController
        let diceId = try #require(root.diceRoot.exportControllable.exportingAll().ids[.dice]?.first)
        let pdfId = await root.pdfRoot.itemControllable.addNew(type: .item)
        let tableId = try #require(root.tableRoot.exportControllable.exportingAll().ids[.table]?.first)

        let diceLink = root.diceRoot.linkControllable.generateLink(linkNumber: 0, itemId: diceId, entryId: nil)
        let pdfLink = root.pdfRoot.linkControllable.generateLink(linkNumber: 0, itemId: pdfId, entryId: nil)
        let tableLink = root.tableRoot.linkControllable.generateLink(linkNumber: 0, itemId: tableId, entryId: nil)

        let characterId = await root.itemController.addNew(type: .item)
        let character = root.itemController.itemOrEmpty(for: characterId)
        character.entries.append(ValueEntryModel.fixture(name: "With Dice Link", value: diceLink))
        character.entries.append(ValueEntryModel.fixture(name: "With Pdf Link", value: pdfLink))
        character.entries.append(ValueEntryModel.fixture(name: tableLink, value: "With Table Link"))

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([characterId]), module: .value))
        let valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(characterId))
        #expect(ids.ids[.dice]?.contains(diceId) == true)
        #expect(ids.ids[.pdf]?.contains(pdfId) == true)
        #expect(ids.ids[.table]?.contains(tableId) == true)
    }

    @Test func exportingItemInCollectionExcludesCollection() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController
        let edit = root.editController

        let collection = await edit.addNew(type: .collection)
        try #require(collection != nil)
        let collectionId = collection!.id

        let itemId = await root.itemController.addNew(type: .item)
        edit.addItem(itemId: itemId, parentId: collectionId)

        let ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .value))
        let valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.contains(itemId))
        #expect(!valueIds!.contains(collectionId))
    }

    @Test func exporting() async throws {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)

        let sut = root.exportController

        let itemId = await root.itemController.addNew(type: .item)

        let newId = await root.itemController.addNew(type: .item)
        let url = root.itemController.itemOrEmpty(for: newId).url(linkNumber: 0)
        let entry = ValueEntryModel(id: UUID(), name: "Nothing", type: .text, value: "\(url)")
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)

        var ids = sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .value))
        var valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.count == 2)
        #expect(valueIds!.contains(itemId))
        #expect(valueIds!.contains(newId))

        let notConnected = await root.itemController.addNew(type: .item)
        ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .value))
        valueIds = ids.ids[.value]
        try #require(valueIds != nil)
        #expect(valueIds!.count == 2)
        #expect(valueIds!.contains(itemId))
        #expect(valueIds!.contains(newId))
        #expect(!valueIds!.contains(notConnected))
    }
}
