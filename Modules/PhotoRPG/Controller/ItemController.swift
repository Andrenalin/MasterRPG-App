// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: ItemControllable, Sendable {
    let container: ModelContainer
    
    func item(for id: UUID) async -> PhotoModel? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.photoModel()
    }
    
    func itemSync(for id: UUID) -> PhotoModel? {
        PhotoDataModel.model(modelContext: ModelContext(container), id: id)?.itemModel
    }

    func modelSync(for id: UUID) -> PhotoDataModel? {
        PhotoDataModel.model(modelContext: ModelContext(container), id: id)
    }

    func allItemIds() -> [UUID] {
        let modelContext = ModelContext(container)
        let fetchDesc = FetchDescriptor<PhotoDataModel>()
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.map { $0.id }
    }
    
    func fileUrl(for id: UUID) async -> FileUrl? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.fileUrl
    }
    
    @MainActor func collections(isFolder: Bool, in parentId: UUID?) -> [PhotoDataModel] {
        let modelContext = ModelContext(container)
        let predicate = #Predicate<PhotoDataModel> { $0.parentId == parentId }
        let fetchDesc = FetchDescriptor<PhotoDataModel>(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.filter { $0.category == (isFolder ? .folder : PhotoDataModel.collectionCategory) }
    }
}
