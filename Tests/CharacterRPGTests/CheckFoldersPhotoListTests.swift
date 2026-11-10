// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

/// A character can have a portrait (`photoId`) and an empty photo list (`photos`). The sheet shows the
/// portrait, but the detail editor lists `photos` and offered "Drop Photo". The editor now lists the
/// portrait, and Validate Data restores the list. The opposite case, a list without a portrait, gets
/// the first photo of the list as its portrait.
@Suite("Photo list of an item with a portrait")
@MainActor
struct CheckFoldersPhotoListTests {
    private func makeRoot() async throws -> CharacterRootModel {
        let root = try await MockRoot.importTestData()
        try await MockRoot.resetTestData(for: root)
        return root
    }

    private func makeItem(in root: CharacterRootModel, photoId: UUID?, photos: [UUID]) async -> UUID {
        let itemId = await root.itemController.addNew(type: .item)
        let item = root.itemController.itemOrEmpty(for: itemId)
        // `.entry`, not the legacy `.character`, which the repair migrates (and tags) on its own.
        item.category = .entry
        item.photoId = photoId
        item.photos = photos
        root.itemController.replace(model: item, isInsert: false)
        return itemId
    }

    private func encoded(_ itemId: UUID, in root: CharacterRootModel) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(root.itemController.itemOrEmpty(for: itemId))
    }

    // MARK: - editorPhotos

    @Test("The editor lists the portrait when the photo list is empty")
    func editorListsThePortraitWithoutList() {
        let photoId = UUID()
        let model = ValueModel(id: UUID(), name: "Rupert", photoId: photoId, photos: [])
        #expect(model.editorPhotos == [photoId])
        #expect(model.photos.isEmpty, "reading does not change the model")
    }

    @Test("The editor lists the photo list when there is one")
    func editorListsThePhotoList() {
        let first = UUID()
        let second = UUID()
        let model = ValueModel(id: UUID(), name: "Rupert", photoId: first, photos: [first, second])
        #expect(model.editorPhotos == [first, second])
    }

    @Test("The editor lists nothing without portrait and list")
    func editorListsNothing() {
        #expect(ValueModel(id: UUID(), name: "Rupert").editorPhotos.isEmpty)
    }

    @Test("A photo list without a portrait is listed as it is")
    func editorListsListWithoutPortrait() {
        let photoId = UUID()
        #expect(ValueModel(id: UUID(), name: "Rupert", photoId: nil, photos: [photoId]).editorPhotos == [photoId])
    }

    // MARK: - repairPhotoList

    @Test("repairPhotoList gives the portrait its list")
    func repairGivesThePortraitItsList() async throws {
        let root = try await makeRoot()
        let photoId = UUID()
        let itemId = await makeItem(in: root, photoId: photoId, photos: [])

        root.editController.repairPhotoList(itemId: itemId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        #expect(item.photos == [photoId])
        #expect(item.photoId == photoId)
    }

    @Test("repairPhotoList makes the first photo of a list the portrait")
    func repairSetsThePortraitFromTheList() async throws {
        let root = try await makeRoot()
        let first = UUID()
        let second = UUID()
        let itemId = await makeItem(in: root, photoId: nil, photos: [first, second])

        root.editController.repairPhotoList(itemId: itemId)

        let item = root.itemController.itemOrEmpty(for: itemId)
        #expect(item.photoId == first)
        #expect(item.photos == [first, second], "the list stays as it is")
    }

    @Test("repairPhotoList leaves an existing list alone")
    func repairKeepsAnExistingList() async throws {
        let root = try await makeRoot()
        let first = UUID()
        let second = UUID()
        let itemId = await makeItem(in: root, photoId: first, photos: [first, second])
        let before = try encoded(itemId, in: root)

        root.editController.repairPhotoList(itemId: itemId)

        #expect(try encoded(itemId, in: root) == before, "nothing is saved")
    }

    @Test("repairPhotoList does nothing without a portrait and a list")
    func repairWithoutPortraitIsNoOp() async throws {
        let root = try await makeRoot()
        let itemId = await makeItem(in: root, photoId: nil, photos: [])
        let before = try encoded(itemId, in: root)

        root.editController.repairPhotoList(itemId: itemId)

        #expect(try encoded(itemId, in: root) == before)
        #expect(root.itemController.itemOrEmpty(for: itemId).photos.isEmpty)
    }

    // MARK: - checkFolders

    @Test("Validate Data restores the photo list of an item with a portrait")
    func checkFoldersRestoresThePhotoList() async throws {
        let root = try await makeRoot()
        let photoId = UUID()
        let itemId = await makeItem(in: root, photoId: photoId, photos: [])

        await root.checkFolders(reportModel: ValidateRepairModel())

        let item = root.itemController.itemOrEmpty(for: itemId)
        #expect(item.photos == [photoId])
        #expect(item.photoId == photoId)
        #expect(item.editorPhotos == [photoId])
    }

    @Test("Validate Data sets the first photo of a list as the portrait")
    func checkFoldersSetsThePortraitFromTheList() async throws {
        let root = try await makeRoot()
        let first = UUID()
        let second = UUID()
        let itemId = await makeItem(in: root, photoId: nil, photos: [first, second])

        await root.checkFolders(reportModel: ValidateRepairModel())

        let item = root.itemController.itemOrEmpty(for: itemId)
        #expect(item.photoId == first)
        #expect(item.photos == [first, second])
    }

    @Test("Validate Data does not change a portrait that is not the first photo")
    func checkFoldersKeepsADifferentPortrait() async throws {
        let root = try await makeRoot()
        let first = UUID()
        let second = UUID()
        let itemId = await makeItem(in: root, photoId: second, photos: [first, second])
        let before = try encoded(itemId, in: root)

        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(try encoded(itemId, in: root) == before)
    }

    @Test("Validate Data keeps the photo lists that are in order")
    func checkFoldersKeepsAnExistingList() async throws {
        let root = try await makeRoot()
        let first = UUID()
        let second = UUID()
        let withList = await makeItem(in: root, photoId: first, photos: [first, second])
        let withoutPhoto = await makeItem(in: root, photoId: nil, photos: [])

        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(root.itemController.itemOrEmpty(for: withList).photos == [first, second])
        #expect(root.itemController.itemOrEmpty(for: withoutPhoto).photos.isEmpty)
        #expect(root.itemController.itemOrEmpty(for: withoutPhoto).photoId == nil)
    }

    @Test("A repeated run leaves a repaired item unchanged", arguments: [true, false])
    func checkFoldersIsStable(portraitOnly: Bool) async throws {
        let root = try await makeRoot()
        let photoId = UUID()
        let itemId = await makeItem(in: root, photoId: portraitOnly ? photoId : nil, photos: portraitOnly ? [] : [photoId, UUID()])

        await root.checkFolders(reportModel: ValidateRepairModel())
        let afterFirst = try encoded(itemId, in: root)
        await root.checkFolders(reportModel: ValidateRepairModel())
        await root.checkFolders(reportModel: ValidateRepairModel())

        #expect(try encoded(itemId, in: root) == afterFirst, "the clocks must not move on a repeated run")
    }

    @Test("A group item is not given a photo list, it loses its portrait", arguments: [false, true])
    func groupItemGetsNoPhotoList(childFirst: Bool) async throws {
        let root = try await makeRoot()
        let ownerId: UUID
        let childId: UUID
        if childFirst {
            childId = await root.itemController.addNew(type: .item)
            ownerId = await root.itemController.addNew(type: .item)
        } else {
            ownerId = await root.itemController.addNew(type: .item)
            childId = await root.itemController.addNew(type: .item)
        }
        let child = root.itemController.itemOrEmpty(for: childId)
        child.category = .entry
        child.displayState = 1
        child.groupId = ownerId
        child.photoId = UUID()
        child.photos = [UUID()]
        root.itemController.replace(model: child, isInsert: false)
        let owner = root.itemController.itemOrEmpty(for: ownerId)
        owner.category = .entry
        owner.entries.append(ValueEntryModel(id: UUID(), name: "Skills", type: .text, value: "", valueId: childId))
        root.itemController.replace(model: owner, isInsert: false)

        await root.checkFolders(reportModel: ValidateRepairModel())
        await root.checkFolders(reportModel: ValidateRepairModel())

        let repaired = root.itemController.itemOrEmpty(for: childId)
        #expect(repaired.photoId == nil)
        #expect(repaired.photos.isEmpty)
    }
}
