// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: ItemControllable, Sendable {
    let container: ModelContainer
    
    func item(for id: UUID) async -> AudioModel? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.photoModel()
    }
    
    func itemSync(for id: UUID) -> AudioModel? {
        AudioDataModel.model(modelContext: ModelContext(container), id: id)?.itemModel
    }

    func modelSync(for id: UUID) -> AudioDataModel? {
        AudioDataModel.model(modelContext: ModelContext(container), id: id)
    }

    func allItemIds() -> [UUID] {
        let modelContext = ModelContext(container)
        let fetchDesc = FetchDescriptor<AudioDataModel>()
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.map { $0.id }
    }
    
    func fileUrl(for id: UUID) async -> FileUrl? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.fileUrl
    }
}
