// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: ItemControllable {
    let container: ModelContainer
    
    func item(for id: UUID) async -> PhotoModel? {
        let actor = PhotoDataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.photoModel()
    }
    
    func itemSync(for id: UUID) -> PhotoModel? {
        PhotoDataModel.model(modelContext: ModelContext(container), id: id)?.photoModel
    }
    
    typealias Model = PhotoModel
    
    func allItemIds() -> [UUID] {
        let modelContext = ModelContext(container)
        let fetchDesc = FetchDescriptor<PhotoDataModel>()
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.map { $0.id }
    }
    
    func fileUrl(for id: UUID) async -> FileUrl? {
        let actor = PhotoDataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.fileUrl
    }
}
