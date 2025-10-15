//// @copyright André Trettin
//
//import Testing
//import SwiftData
//@testable import CoreRPG
//import Foundation
//
//struct EditControllerTests {
//
//    @MainActor
//    func makeRoot() throws -> FakeItemRootController {
//        let modelContainer = try ModelContainer(for: ItemDataModel.self, TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
//        return FakeItemRootController(modelContext: modelContainer.mainContext, module: .photo)
//    }
//    
//    @MainActor
//    func models(in root: FakeItemRootController) -> [ItemDataModel] {
//        let ids = root.itemControllable.allItemIds()
//        return ids.compactMap {
//            ItemDataModel.model(modelContext: root.modelContext, id: $0)
//        }
//    }
//    
//    @MainActor
//    @Test func addNewPhotoItem() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//        let model = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item)
//        #expect(model.category == .all)
//        #expect(models(in: root).count == 1)
//    }
//
//    @MainActor
//    @Test func addNewAlbum() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//        let model = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
//        #expect(model.category == .album)
//        #expect(models(in: root).count == 1)
//    }
//
//    @MainActor
//    @Test func addNewFolder() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//        let model = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
//        #expect(model.category == .folder)
//        #expect(models(in: root).count == 1)
//    }
//
//    @MainActor
//    @Test func addComplexFolderHierarchy() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//
//        // Create a main folder
//        let folder = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
//        #expect(folder.category == .folder)
//        #expect(models(in: root).count == 1)
//
//        // Create subfolder and album
//        let subfolder = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
//        let album = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
//        #expect(subfolder.category == .folder)
//        #expect(album.category == .album)
//
//        // Add subfolder and album as children to main folder
//        root.editControllable.addItem(itemId: subfolder.id, in: root.modelContext, parentId: folder.id, folderId: nil)
//        root.editControllable.addItem(itemId: album.id, in: root.modelContext, parentId: folder.id, folderId: nil)
//
//        // Add photo item to subfolder and to album
//        let photo1 = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item)
//        let photo2 = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item)
//        root.editControllable.addItem(itemId: photo1.id, in: root.modelContext, parentId: subfolder.id, folderId: nil)
//        root.editControllable.addItem(itemId: photo2.id, in: root.modelContext, parentId: album.id, folderId: nil)
//
//        // Fetch updated models
//        let allModels = models(in: root)
//        let folderModel = allModels.first { $0.id == folder.id }
//        let subfolderModel = allModels.first { $0.id == subfolder.id }
//        let albumModel = allModels.first { $0.id == album.id }
//        
//        try #require(folderModel != nil)
//        try #require(subfolderModel != nil)
//        try #require(albumModel != nil)
//
//        // Check folder contains subfolder and album
//        let folderChildren = folderModel!.entries.map { $0.childId }
//        #expect(folderChildren.contains(subfolder.id))
//        #expect(folderChildren.contains(album.id))
//
//        // Check subfolder contains its photo
//        let subfolderChildren = subfolderModel!.entries.map { $0.childId }
//        #expect(subfolderChildren.contains(photo1.id))
//
//        // Check album contains its photo
//        let albumChildren = albumModel!.entries.map { $0.childId }
//        #expect(albumChildren.contains(photo2.id))
//    }
//
//    @MainActor
//    @Test func cannotAddFolderAsItsOwnChild() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//
//        // Create a folder
//        let folder = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
//        #expect(folder.category == .folder)
//        #expect(models(in: root).count == 1)
//
//        // Attempt to add the folder as its own child
//        root.editControllable.addItem(itemId: folder.id, in: root.modelContext, parentId: folder.id, folderId: nil)
//
//        // Fetch updated model for the folder
//        let folderModel = models(in: root).first { $0.id == folder.id }
//        try #require(folderModel != nil)
//        let children = folderModel!.entries.map { $0.childId }
//        #expect(!children.contains(folder.id), "A folder should not be able to contain itself as a child.")
//    }
//
//    @MainActor
//    @Test func photosSharedBetweenAlbumsNotDeletedWithAlbum() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//
//        // Create two albums
//        let album1 = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
//        let album2 = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
//        #expect(album1.category == .album)
//        #expect(album2.category == .album)
//
//        // Create two photos
//        let photo1 = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item)
//        let photo2 = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item)
//        #expect(photo1.category == .all) // Assuming .adventure is the photo category
//        #expect(photo2.category == .all)
//
//        // Add both photos to album1
//        root.editControllable.addItem(itemId: photo1.id, in: root.modelContext, parentId: album1.id, folderId: nil)
//        root.editControllable.addItem(itemId: photo2.id, in: root.modelContext, parentId: album1.id, folderId: nil)
//
//        // Add both photos to album2
//        root.editControllable.addItem(itemId: photo1.id, in: root.modelContext, parentId: album2.id, folderId: nil)
//        root.editControllable.addItem(itemId: photo2.id, in: root.modelContext, parentId: album2.id, folderId: nil)
//
//        // Check both albums contain both photos
//        let allModels = models(in: root)
//        let album1Model = allModels.first { $0.id == album1.id }
//        let album2Model = allModels.first { $0.id == album2.id }
//        try #require(album1Model != nil)
//        try #require(album2Model != nil)
//        let album1Children = album1Model!.entries.map { $0.childId }
//        let album2Children = album2Model!.entries.map { $0.childId }
//        #expect(album1Children.contains(photo1.id))
//        #expect(album1Children.contains(photo2.id))
//        #expect(album2Children.contains(photo1.id))
//        #expect(album2Children.contains(photo2.id))
//
//        guard let album1Model else { return }
//        // Remove both photos from album1
//        root.editControllable.removeItem(offsets: IndexSet(integer: 1), model:album1Model)
//        root.editControllable.removeItem(offsets: IndexSet(integer: 0), model:album1Model)
//        let album1ModelAfterRemoval = models(in: root).first { $0.id == album1.id }!
//        let album1ChildrenAfterRemoval = album1ModelAfterRemoval.entries.map { $0.childId }
//        #expect(!album1ChildrenAfterRemoval.contains(photo1.id))
//        #expect(!album1ChildrenAfterRemoval.contains(photo2.id))
//
//        // Both photos should still exist and be present in album2
//        let allModelsAfterRemoval = models(in: root)
//        let photo1Exists = allModelsAfterRemoval.contains { $0.id == photo1.id }
//        let photo2Exists = allModelsAfterRemoval.contains { $0.id == photo2.id }
//        let album2ModelAfterRemoval = allModelsAfterRemoval.first { $0.id == album2.id }!
//        let album2ChildrenAfterRemoval = album2ModelAfterRemoval.entries.map { $0.childId }
//        #expect(photo1Exists)
//        #expect(photo2Exists)
//        #expect(album2ChildrenAfterRemoval.contains(photo1.id))
//        #expect(album2ChildrenAfterRemoval.contains(photo2.id))
//
//        // Delete album2
//        root.editControllable.delete(itemId: album2Model?.id ?? UUID())
//        let allModelsAfterAlbumDeletion = models(in: root)
//        let photo1StillExists = allModelsAfterAlbumDeletion.contains { $0.id == photo1.id }
//        let photo2StillExists = allModelsAfterAlbumDeletion.contains { $0.id == photo2.id }
//        #expect(photo1StillExists, "Photo 1 should not be deleted with the album.")
//        #expect(photo2StillExists, "Photo 2 should not be deleted with the album.")
//    }
//
//    @MainActor
//    @Test func albumCannotContainFoldersOrAlbums() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//
//        // Create an album, a folder, and another album
//        let album = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
//        let folder = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .folder)
//        let album2 = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .collection)
//        #expect(album.category == .album)
//        #expect(folder.category == .folder)
//        #expect(album2.category == .album)
//
//        // Attempt to add a folder to the album
//        root.editControllable.addItem(itemId: folder.id, in: root.modelContext, parentId: album.id, folderId: nil)
//        // Attempt to add another album to the album
//        root.editControllable.addItem(itemId: album2.id, in: root.modelContext, parentId: album.id, folderId: nil)
//
//        // Fetch updated album model and children
//        let albumModel = models(in: root).first { $0.id == album.id }
//        try #require(albumModel != nil)
//        let albumChildren = albumModel!.entries.map { $0.childId }
//        // Verify neither folder nor album2 were added as children
//        #expect(!albumChildren.contains(folder.id), "Folder should not be added to album.")
//        #expect(!albumChildren.contains(album2.id), "Album should not be added to album.")
//    }
//    
//    @MainActor
//    @Test func groupCannotAddItselfAsChild() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//
//        // Create a group (using folder for group if that's the mapping)
//        let groupPhoto = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item) // Change to .group if available
//        #expect(models(in: root).count == 1)
//
//        // If there's a dedicated addGroup method
//        root.editControllable.addGroup(childId: groupPhoto.id, model: groupPhoto)
//        #expect(groupPhoto.displayState == 0)
//        
//        let children = groupPhoto.entries.map { $0.childId }
//        #expect(!children.contains(groupPhoto.id), "A group should not be able to contain itself as a child.")
//    }
//    
//    @MainActor
//    @Test func addPhotoAsGroupChildHidesItAndLinks() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//
//        // Create two photo items
//        let parent = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item)
//        let child = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item)
//        #expect(parent.category == .all)
//        #expect(child.category == .all)
//
//        // Add child photo as group to parent photo
//        root.editControllable.addGroup(childId: child.id, model: parent)
//
//        // Fetch updated models
//        let allModels = models(in: root)
//        let parentModel = allModels.first { $0.id == parent.id }
//        let childModel = allModels.first { $0.id == child.id }
//        try #require(parentModel != nil)
//        try #require(childModel != nil)
//        
//        // Check child is hidden (displayState == 1)
//        #expect(childModel!.displayState == 1, "Child photo should be hidden after grouping.")
//        // Check parent's children contain the child
//        let parentChildren = parentModel!.entries.map { $0.childId }
//        #expect(parentChildren.contains(child.id), "Parent should contain the child in its entries.")
//    }
//    
//    @MainActor
//    @Test func removeGroupPhotoRestoresVisibilityAndChildCannotRemoveSelf() async throws {
//        let root = try makeRoot()
//        #expect(models(in: root).isEmpty)
//
//        // Create two photo items
//        let parent = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item)
//        let child = root.editControllable.addNew(modelContext: root.modelContext, module: .photo, type: .item)
//        #expect(parent.category == .all)
//        #expect(child.category == .all)
//
//        // Add child photo as group to parent photo
//        root.editControllable.addGroup(childId: child.id, model: parent)
//        var allModels = models(in: root)
//        let parentModel = allModels.first { $0.id == parent.id }
//        try #require(parentModel != nil)
//        
//        var childModel = allModels.first { $0.id == child.id }!
//        #expect(childModel.displayState == 1, "Child photo should be hidden after grouping.")
//        let parentChildren = parentModel!.entries.map { $0.childId }
//        #expect(parentChildren.contains(child.id), "Parent should contain the child in its entries.")
//
//        // Child cannot remove itself (should not crash or remove itself from itself)
//        root.editControllable.removeGroup(childId: child.id, model: childModel)
//        #expect(childModel.displayState == 1, "A child should not be able to remove itself as its own group.")
//
//        guard let parentModel else { return }
//        // Remove the child from group
//        root.editControllable.removeGroup(childId: child.id, model: parentModel)
//        allModels = models(in: root)
//        childModel = allModels.first { $0.id == child.id }!
//        #expect(childModel.displayState == 0, "Child photo should become visible when removed from group.")
//        let parentChildrenAfterRemoval = allModels.first { $0.id == parent.id }!.entries.map { $0.childId }
//        #expect(!parentChildrenAfterRemoval.contains(child.id), "Child should no longer be in parent's children list after removal.")
//    }
//}
