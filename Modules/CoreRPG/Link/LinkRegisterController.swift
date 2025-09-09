// @copyright André Trettin

import Foundation
import SwiftData

@MainActor
struct LinkRegisterController {
    let container: ModelContainer
    
    init(container: ModelContainer) {
        self.container = container
    }
}

extension LinkRegisterController {
    func register(link: LinkReplaceModel, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules) -> UUID {
        let model = LinkDataModel(name: link.name, sourceId: link.itemId, sourceEntryId: link.entryId, sourceModule: link.module, destinationId: destinationId, destinationEntryId: destinationEntryId, destinationModel: destinationModule)
        container.mainContext.insert(model)
        try? container.mainContext.save()
        return model.id
    }
        
    func remove(linkId: UUID) {
        let predicate = #Predicate<LinkDataModel> {
            $0.id == linkId
        }
        let fetchDescription = FetchDescriptor<LinkDataModel>(predicate: predicate)
        let models = try? container.mainContext.fetch(fetchDescription)
        models?.forEach {
            container.mainContext.delete($0)
        }
        try? container.mainContext.save()
    }
    
    func register(sourceId: UUID, sourceEntryId: UUID? = nil, sourceModule: NetworkModules, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules) -> UUID {
        let model = LinkDataModel(
            name: destinationModule.title,
            sourceId: sourceId,
            sourceEntryId: sourceEntryId,
            sourceModule: sourceModule,
            destinationId: destinationId,
            destinationEntryId: destinationEntryId,
            destinationModel: destinationModule
        )
        container.mainContext.insert(model)
        try? container.mainContext.save()
        return model.id
    }
    
    func effectedItems(targetId: UUID, targetEntryId: UUID? = nil, targetModule: NetworkModules) -> [EffectedItemModel] {
        let predicate: Predicate<LinkDataModel>
        if let targetEntryId {
            predicate = #Predicate<LinkDataModel> {
                $0.destinationId == targetId && $0.destinationEntryId == targetEntryId && $0.destinationModule == targetModule
            }
        } else {
            predicate = #Predicate<LinkDataModel> {
                $0.destinationId == targetId && $0.destinationModule == targetModule
            }
        }
        let fetchDescription = FetchDescriptor<LinkDataModel>(predicate: predicate)
        guard let models = try? container.mainContext.fetch(fetchDescription) else { return [] }
        
        return models.map {
            EffectedItemModel(id: $0.id, name: $0.name, entryName: nil, module: $0.sourceModule)
        }
    }
}
