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
    func register(link: LinkReplaceModel, targetId: UUID, targetEntryId: UUID? = nil, targetModule: NetworkModules) {
        let model = LinkDataModel(name: link.name, sourceId: link.itemId, sourceEntryId: link.entryId, sourceModule: link.module, destinationId: targetId, destinationEntryId: targetEntryId, destinationModel: targetModule)
        container.mainContext.insert(model)
        try? container.mainContext.save()
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
