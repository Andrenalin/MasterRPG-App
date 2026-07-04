// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import PhotoRPG

@MainActor
struct ExportControllerTests {
    @Test func exportingAll() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        var ids = sut.exportingAll()
        try #require(ids.ids[.photo] != nil)
        #expect(ids.ids[.photo]!.isEmpty)
        
        let itemId = await root.itemController.addNew(type: .item)
        ids = sut.exportingAll()
        try #require(ids.ids[.photo] != nil)
        #expect(ids.ids[.photo]! == [itemId])
        
        let newId = await root.itemController.addNew(type: .item)
        let entry = PhotoEntryModel(id: UUID(), photoId: newId)
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)
        
        ids = sut.exportingAll()
        try #require(ids.ids[.photo] != nil)
        #expect(ids.ids[.photo]!.count == 2)
    }
    
    @Test func exporting() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        let itemId = await root.itemController.addNew(type: .item)
        
        let newId = await root.itemController.addNew(type: .item)
        let entry = PhotoEntryModel(id: UUID(), photoId: newId)
        root.itemController.itemOrEmpty(for: itemId).entries.append(entry)
        
        var ids = sut.exporting(itemIds: ItemModuleIds(ids: Set(arrayLiteral: itemId), module: .photo))
        var photoIds = ids.ids[.photo]
        try #require(photoIds != nil)
        #expect(photoIds!.count == 2)
        #expect(photoIds!.contains(itemId))
        #expect(photoIds!.contains(newId))
        
        let notConnected = await root.itemController.addNew(type: .item)
        ids = sut.exporting(itemIds: ItemModuleIds(ids: Set([itemId]), module: .photo))
        photoIds = ids.ids[.photo]
        try #require(photoIds != nil)
        #expect(photoIds!.count == 2)
        #expect(photoIds!.contains(itemId))
        #expect(photoIds!.contains(newId))
        #expect(!photoIds!.contains(notConnected))
    }
    
    // MARK: - exporting(itemIds:) Tests
    
    @Test("Exporting with empty item IDs returns empty result")
    func exportingWithEmptyIds() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        let emptyIds = ItemModuleIds()
        let result = sut.exporting(itemIds: emptyIds)
        
        #expect(result.ids[.photo, default: []].isEmpty)
    }
    
    @Test("Exporting single item without entries returns that item")
    func exportingSingleItemWithoutEntries() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        // Create a photo item without entries
        let photoId = await root.itemController.addNew(type: .item)
        let photo = root.itemController.itemOrEmpty(for: photoId)
        photo.name = "Test Photo"
        root.itemController.replace(model: photo, isInsert: false)
        
        let inputIds = ItemModuleIds(ids: [photoId], module: .photo)
        let result = sut.exporting(itemIds: inputIds)
        
        let resultIds = result.ids[.photo, default: []]
        #expect(resultIds.count == 1)
        #expect(resultIds.contains(photoId))
    }
    
    @Test("Exporting item with entries includes referenced photo IDs")
    func exportingItemWithEntriesIncludesReferencedPhotos() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        // Create referenced photo items
        let referencedPhotoId1 = await root.itemController.addNew(type: .item)
        let referencedPhoto1 = root.itemController.itemOrEmpty(for: referencedPhotoId1)
        referencedPhoto1.name = "Referenced Photo 1"
        root.itemController.replace(model: referencedPhoto1, isInsert: false)
        
        let referencedPhotoId2 = await root.itemController.addNew(type: .item)
        let referencedPhoto2 = root.itemController.itemOrEmpty(for: referencedPhotoId2)
        referencedPhoto2.name = "Referenced Photo 2"
        root.itemController.replace(model: referencedPhoto2, isInsert: false)
        
        // Create main photo with entries referencing other photos
        let mainPhotoId = await root.itemController.addNew(type: .item)
        let mainPhoto = root.itemController.itemOrEmpty(for: mainPhotoId)
        mainPhoto.name = "Main Photo"
        mainPhoto.entries = [
            PhotoEntryModel(id: UUID(), photoId: referencedPhotoId1),
            PhotoEntryModel(id: UUID(), photoId: referencedPhotoId2)
        ]
        root.itemController.replace(model: mainPhoto, isInsert: false)
        
        let inputIds = ItemModuleIds(ids: [mainPhotoId], module: .photo)
        let result = sut.exporting(itemIds: inputIds)
        
        let resultIds = result.ids[.photo, default: []]
        #expect(resultIds.count == 3)
        #expect(resultIds.contains(mainPhotoId))
        #expect(resultIds.contains(referencedPhotoId1))
        #expect(resultIds.contains(referencedPhotoId2))
    }
    
    @Test("Exporting handles circular references without infinite loop")
    func exportingHandlesCircularReferences() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        // Create two photos that reference each other
        let photoId1 = await root.itemController.addNew(type: .item)
        let photoId2 = await root.itemController.addNew(type: .item)
        
        let photo1 = root.itemController.itemOrEmpty(for: photoId1)
        photo1.name = "Photo 1"
        photo1.entries = [PhotoEntryModel(id: UUID(), photoId: photoId2)]
        root.itemController.replace(model: photo1, isInsert: false)
        
        let photo2 = root.itemController.itemOrEmpty(for: photoId2)
        photo2.name = "Photo 2"
        photo2.entries = [PhotoEntryModel(id: UUID(), photoId: photoId1)]
        root.itemController.replace(model: photo2, isInsert: false)
        
        let inputIds = ItemModuleIds(ids: [photoId1], module: .photo)
        let result = sut.exporting(itemIds: inputIds)
        
        let resultIds = result.ids[.photo, default: []]
        #expect(resultIds.count == 2)
        #expect(resultIds.contains(photoId1))
        #expect(resultIds.contains(photoId2))
    }
    
    @Test("Exporting handles self-referencing entries")
    func exportingHandlesSelfReferencingEntries() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        // Create a photo that references itself
        let photoId = await root.itemController.addNew(type: .item)
        let photo = root.itemController.itemOrEmpty(for: photoId)
        photo.name = "Self-Referencing Photo"
        photo.entries = [PhotoEntryModel(id: UUID(), photoId: photoId)]
        root.itemController.replace(model: photo, isInsert: false)
        
        let inputIds = ItemModuleIds(ids: [photoId], module: .photo)
        let result = sut.exporting(itemIds: inputIds)
        
        let resultIds = result.ids[.photo, default: []]
        #expect(resultIds.count == 1)
        #expect(resultIds.contains(photoId))
    }
    
    @Test("Exporting multiple items collects all referenced photos")
    func exportingMultipleItemsCollectsAllReferencedPhotos() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        // Create shared referenced photo
        let sharedPhotoId = await root.itemController.addNew(type: .item)
        let sharedPhoto = root.itemController.itemOrEmpty(for: sharedPhotoId)
        sharedPhoto.name = "Shared Photo"
        root.itemController.replace(model: sharedPhoto, isInsert: false)
        
        // Create unique referenced photo for item 1
        let uniquePhotoId1 = await root.itemController.addNew(type: .item)
        let uniquePhoto1 = root.itemController.itemOrEmpty(for: uniquePhotoId1)
        uniquePhoto1.name = "Unique Photo 1"
        root.itemController.replace(model: uniquePhoto1, isInsert: false)
        
        // Create unique referenced photo for item 2
        let uniquePhotoId2 = await root.itemController.addNew(type: .item)
        let uniquePhoto2 = root.itemController.itemOrEmpty(for: uniquePhotoId2)
        uniquePhoto2.name = "Unique Photo 2"
        root.itemController.replace(model: uniquePhoto2, isInsert: false)
        
        // Create main photo 1
        let mainPhotoId1 = await root.itemController.addNew(type: .item)
        let mainPhoto1 = root.itemController.itemOrEmpty(for: mainPhotoId1)
        mainPhoto1.name = "Main Photo 1"
        mainPhoto1.entries = [
            PhotoEntryModel(id: UUID(), photoId: sharedPhotoId),
            PhotoEntryModel(id: UUID(), photoId: uniquePhotoId1)
        ]
        root.itemController.replace(model: mainPhoto1, isInsert: false)
        
        // Create main photo 2
        let mainPhotoId2 = await root.itemController.addNew(type: .item)
        let mainPhoto2 = root.itemController.itemOrEmpty(for: mainPhotoId2)
        mainPhoto2.name = "Main Photo 2"
        mainPhoto2.entries = [
            PhotoEntryModel(id: UUID(), photoId: sharedPhotoId),
            PhotoEntryModel(id: UUID(), photoId: uniquePhotoId2)
        ]
        root.itemController.replace(model: mainPhoto2, isInsert: false)
        
        let inputIds = ItemModuleIds(ids: [mainPhotoId1, mainPhotoId2], module: .photo)
        let result = sut.exporting(itemIds: inputIds)
        
        let resultIds = result.ids[.photo, default: []]
        #expect(resultIds.count == 5)
        #expect(resultIds.contains(mainPhotoId1))
        #expect(resultIds.contains(mainPhotoId2))
        #expect(resultIds.contains(sharedPhotoId))
        #expect(resultIds.contains(uniquePhotoId1))
        #expect(resultIds.contains(uniquePhotoId2))
    }
    
    @Test("Exporting skips entries referencing non-existent items")
    func exportingSkipsNonExistentReferencedItems() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        let nonExistentId = UUID()
        
        // Create main photo with entry referencing non-existent item
        let mainPhotoId = await root.itemController.addNew(type: .item)
        let mainPhoto = root.itemController.itemOrEmpty(for: mainPhotoId)
        mainPhoto.name = "Main Photo"
        mainPhoto.entries = [
            PhotoEntryModel(id: UUID(), photoId: nonExistentId)
        ]
        root.itemController.replace(model: mainPhoto, isInsert: false)
        
        let inputIds = ItemModuleIds(ids: [mainPhotoId], module: .photo)
        let result = sut.exporting(itemIds: inputIds)
        
        let resultIds = result.ids[.photo, default: []]
        #expect(resultIds.count == 1)
        #expect(resultIds.contains(mainPhotoId))
        #expect(!resultIds.contains(nonExistentId))
    }
    
    @Test("Exporting handles deeply nested references")
    func exportingHandlesDeeplyNestedReferences() async throws {
        let root = PhotoRootModel.testRoot()
        await root.itemController.resetData()
        
        let sut = root.exportController
        
        // Create a chain of photos: photo1 -> photo2 -> photo3 -> photo4
        let photoId4 = await root.itemController.addNew(type: .item)
        let photo4 = root.itemController.itemOrEmpty(for: photoId4)
        photo4.name = "Photo 4 (Leaf)"
        root.itemController.replace(model: photo4, isInsert: false)
        
        let photoId3 = await root.itemController.addNew(type: .item)
        let photo3 = root.itemController.itemOrEmpty(for: photoId3)
        photo3.name = "Photo 3"
        photo3.entries = [PhotoEntryModel(id: UUID(), photoId: photoId4)]
        root.itemController.replace(model: photo3, isInsert: false)
        
        let photoId2 = await root.itemController.addNew(type: .item)
        let photo2 = root.itemController.itemOrEmpty(for: photoId2)
        photo2.name = "Photo 2"
        photo2.entries = [PhotoEntryModel(id: UUID(), photoId: photoId3)]
        root.itemController.replace(model: photo2, isInsert: false)
        
        let photoId1 = await root.itemController.addNew(type: .item)
        let photo1 = root.itemController.itemOrEmpty(for: photoId1)
        photo1.name = "Photo 1 (Root)"
        photo1.entries = [PhotoEntryModel(id: UUID(), photoId: photoId2)]
        root.itemController.replace(model: photo1, isInsert: false)
        
        let inputIds = ItemModuleIds(ids: [photoId1], module: .photo)
        let result = sut.exporting(itemIds: inputIds)
        
        let resultIds = result.ids[.photo, default: []]
        #expect(resultIds.count == 4)
        #expect(resultIds.contains(photoId1))
    }
}
