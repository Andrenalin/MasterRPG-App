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
}
