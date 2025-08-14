// @copyright André Trettin

import Testing
import SwiftData
@testable import CoreRPG
@testable import PhotoRPG
import Foundation

struct EditControllerTests {

    @MainActor
    func makeRoot() throws -> PhotoRootModel {
        let modelContainer = try ModelContainer(for: PhotoDataModel.self, TagDataModel.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        return PhotoRootModel(modelContext: modelContainer.mainContext)
    }
    
    @MainActor
    func models(in root: PhotoRootModel) -> [PhotoDataModel] {
        let ids = root.itemController.allItemIds()
        return ids.compactMap {
            PhotoDataModel.model(modelContext: root.modelContext, id: $0)
        }
    }
    
    @MainActor
    @Test func addNewPhotoItem() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)
        let model = root.editController.addNew(modelContext: root.modelContext, type: .item)        
        #expect(model.category == .adventure)
        #expect(models(in: root).count == 1)
    }

    @MainActor
    @Test func addNewAlbum() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)
        let model = root.editController.addNew(modelContext: root.modelContext, type: .collection)
        #expect(model.category == .album)
        #expect(models(in: root).count == 1)
    }

    @MainActor
    @Test func addNewFolder() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)
        let model = root.editController.addNew(modelContext: root.modelContext, type: .folder)
        #expect(model.category == .folder)
        #expect(models(in: root).count == 1)
    }

    @MainActor
    @Test func addComplexFolderHierarchy() async throws {
        let root = try makeRoot()
        #expect(models(in: root).isEmpty)

        // Create a main folder
        let folder = root.editController.addNew(modelContext: root.modelContext, type: .folder)
        #expect(folder.category == .folder)
        #expect(models(in: root).count == 1)

        // Create subfolder and album
        let subfolder = root.editController.addNew(modelContext: root.modelContext, type: .folder)
        let album = root.editController.addNew(modelContext: root.modelContext, type: .collection)
        #expect(subfolder.category == .folder)
        #expect(album.category == .album)

        // Add subfolder and album as children to main folder
        root.editController.addItem(itemId: subfolder.id, in: root.modelContext, parentId: folder.id, folderId: nil)
        root.editController.addItem(itemId: album.id, in: root.modelContext, parentId: folder.id, folderId: nil)

        // Add photo item to subfolder and to album
        let photo1 = root.editController.addNew(modelContext: root.modelContext, type: .item)
        let photo2 = root.editController.addNew(modelContext: root.modelContext, type: .item)
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
}
