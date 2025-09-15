// @copyright André Trettin

import Testing
import SwiftData
@testable import CoreRPG
@testable import PhotoRPG
import Foundation

struct EditControllerTests {

    @MainActor
    func makeRoot() throws -> PhotoRootModel {
        let modelContainer = try ModelContainer(for: ItemDataModel.self, LinkDataModel.self, TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return PhotoRootModel(modelContext: modelContainer.mainContext)
    }
    
    @MainActor
    func models(in root: PhotoRootModel) -> [ItemDataModel] {
        let ids = root.itemController.allItemIds()
        return ids.compactMap {
            ItemDataModel.model(modelContext: root.modelContext, id: $0)
        }
    }
    
    @MainActor
    @Test func addNewPhotoItem() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)
        let model = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .item)        
        #expect(model.category == .item)
        #expect(models(in: root).count == 1)
    }

    @MainActor
    @Test func addNewAlbum() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)
        let model = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
        #expect(model.category == .album)
        #expect(models(in: root).count == 1)
    }

    @MainActor
    @Test func addNewFolder() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)
        let model = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
        #expect(model.category == .folder)
        #expect(models(in: root).count == 1)
    }

    @MainActor
    @Test func addComplexFolderHierarchy() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)

        // Create a main folder
        let folder = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
        #expect(folder.category == .folder)
        #expect(models(in: root).count == 1)

        // Create subfolder and album
        let subfolder = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
        let album = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
        #expect(subfolder.category == .folder)
        #expect(album.category == .album)

        // Add subfolder and album as children to main folder
        root.editController.addItem(itemId: subfolder.id, in: root.modelContext, parentId: folder.id, folderId: nil)
        root.editController.addItem(itemId: album.id, in: root.modelContext, parentId: folder.id, folderId: nil)

        // Add photo item to subfolder and to album
        let photo1 = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .item)
        let photo2 = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .item)
        root.editController.addItem(itemId: photo1.id, in: root.modelContext, parentId: subfolder.id, folderId: nil)
        root.editController.addItem(itemId: photo2.id, in: root.modelContext, parentId: album.id, folderId: nil)

        // Fetch updated models
        let allModels = models(in: root)
        let folderModel = allModels.first { $0.id == folder.id }!
        let subfolderModel = allModels.first { $0.id == subfolder.id }!
        let albumModel = allModels.first { $0.id == album.id }!

        // Check folder contains subfolder and album
        let folderChildren = folderModel.entries.map { $0.childId }
        #expect(folderChildren.contains(subfolder.id))
        #expect(folderChildren.contains(album.id))

        // Check subfolder contains its photo
        let subfolderChildren = subfolderModel.entries.map { $0.childId }
        #expect(subfolderChildren.contains(photo1.id))

        // Check album contains its photo
        let albumChildren = albumModel.entries.map { $0.childId }
        #expect(albumChildren.contains(photo2.id))
    }

    @MainActor
    @Test func cannotAddFolderAsItsOwnChild() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)

        // Create a folder
        let folder = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
        #expect(folder.category == .folder)
        #expect(models(in: root).count == 1)

        // Attempt to add the folder as its own child
        root.editController.addItem(itemId: folder.id, in: root.modelContext, parentId: folder.id, folderId: nil)

        // Fetch updated model for the folder
        let folderModel = models(in: root).first { $0.id == folder.id }!
        let children = folderModel.entries.map { $0.childId }
        #expect(!children.contains(folder.id), "A folder should not be able to contain itself as a child.")
    }

    @MainActor
    @Test func photosSharedBetweenAlbumsNotDeletedWithAlbum() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)

        // Create two albums
        let album1 = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
        let album2 = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
        #expect(album1.category == .album)
        #expect(album2.category == .album)

        // Create two photos
        let photo1 = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .item)
        let photo2 = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .item)
        #expect(photo1.category == .item) // Assuming .adventure is the photo category
        #expect(photo2.category == .item)

        // Add both photos to album1
        root.editController.addItem(itemId: photo1.id, in: root.modelContext, parentId: album1.id, folderId: nil)
        root.editController.addItem(itemId: photo2.id, in: root.modelContext, parentId: album1.id, folderId: nil)

        // Add both photos to album2
        root.editController.addItem(itemId: photo1.id, in: root.modelContext, parentId: album2.id, folderId: nil)
        root.editController.addItem(itemId: photo2.id, in: root.modelContext, parentId: album2.id, folderId: nil)

        // Check both albums contain both photos
        let allModels = models(in: root)
        let album1Model = allModels.first { $0.id == album1.id }!
        let album2Model = allModels.first { $0.id == album2.id }!
        let album1Children = album1Model.entries.map { $0.childId }
        let album2Children = album2Model.entries.map { $0.childId }
        #expect(album1Children.contains(photo1.id))
        #expect(album1Children.contains(photo2.id))
        #expect(album2Children.contains(photo1.id))
        #expect(album2Children.contains(photo2.id))

        // Remove both photos from album1
        root.editController.removeItem(offsets: IndexSet(integer: 1), model:album1Model)
        root.editController.removeItem(offsets: IndexSet(integer: 0), model:album1Model)
        let album1ModelAfterRemoval = models(in: root).first { $0.id == album1.id }!
        let album1ChildrenAfterRemoval = album1ModelAfterRemoval.entries.map { $0.childId }
        #expect(!album1ChildrenAfterRemoval.contains(photo1.id))
        #expect(!album1ChildrenAfterRemoval.contains(photo2.id))

        // Both photos should still exist and be present in album2
        let allModelsAfterRemoval = models(in: root)
        let photo1Exists = allModelsAfterRemoval.contains { $0.id == photo1.id }
        let photo2Exists = allModelsAfterRemoval.contains { $0.id == photo2.id }
        let album2ModelAfterRemoval = allModelsAfterRemoval.first { $0.id == album2.id }!
        let album2ChildrenAfterRemoval = album2ModelAfterRemoval.entries.map { $0.childId }
        #expect(photo1Exists)
        #expect(photo2Exists)
        #expect(album2ChildrenAfterRemoval.contains(photo1.id))
        #expect(album2ChildrenAfterRemoval.contains(photo2.id))

        // Delete album2
        root.editController.delete(model: album2Model)
        let allModelsAfterAlbumDeletion = models(in: root)
        let photo1StillExists = allModelsAfterAlbumDeletion.contains { $0.id == photo1.id }
        let photo2StillExists = allModelsAfterAlbumDeletion.contains { $0.id == photo2.id }
        #expect(photo1StillExists, "Photo 1 should not be deleted with the album.")
        #expect(photo2StillExists, "Photo 2 should not be deleted with the album.")
    }

    @MainActor
    @Test func albumCannotContainFoldersOrAlbums() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)

        // Create an album, a folder, and another album
        let album = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
        let folder = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
        let album2 = root.editController.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
        #expect(album.category == .album)
        #expect(folder.category == .folder)
        #expect(album2.category == .album)

        // Attempt to add a folder to the album
        root.editController.addItem(itemId: folder.id, in: root.modelContext, parentId: album.id, folderId: nil)
        // Attempt to add another album to the album
        root.editController.addItem(itemId: album2.id, in: root.modelContext, parentId: album.id, folderId: nil)

        // Fetch updated album model and children
        let albumModel = models(in: root).first { $0.id == album.id }!
        let albumChildren = albumModel.entries.map { $0.childId }
        // Verify neither folder nor album2 were added as children
        #expect(!albumChildren.contains(folder.id), "Folder should not be added to album.")
        #expect(!albumChildren.contains(album2.id), "Album should not be added to album.")
    }
}
