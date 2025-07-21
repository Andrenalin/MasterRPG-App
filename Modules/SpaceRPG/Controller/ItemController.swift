// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: ItemControllable {
    let container: ModelContainer
    
    func item(for id: UUID) async -> SpaceModel? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.spaceModel()
    }
    
    func itemSync(for id: UUID) -> SpaceModel? {
        modelSync(for: id)?.spaceModel
    }

    func modelSync(for id: UUID) -> SpaceDataModel? {
        SpaceDataModel.model(modelContext: ModelContext(container), id: id)
    }

    func allItemIds() -> [UUID] {
        let modelContext = ModelContext(container)
        let fetchDesc = FetchDescriptor<SpaceDataModel>()
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.map { $0.id }
    }
    
    func fileUrl(for id: UUID) async -> FileUrl? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.fileUrl
    }
}
