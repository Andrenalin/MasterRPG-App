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
        // Check if link already exists
        let predicate = #Predicate<LinkDataModel> {
            $0.sourceId == link.itemId && 
            $0.sourceEntryId == link.entryId && 
            $0.sourceModule == link.module && 
            $0.destinationId == destinationId && 
            $0.destinationEntryId == destinationEntryId && 
            $0.destinationModule == destinationModule
        }
        let fetchDescriptor = FetchDescriptor<LinkDataModel>(predicate: predicate)
        
        if let existingLink = try? container.mainContext.fetch(fetchDescriptor).first {
            return existingLink.id
        }
        
        // Create new link if it doesn't exist
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
        // Check if link already exists
        let predicate = #Predicate<LinkDataModel> {
            $0.sourceId == sourceId && 
            $0.sourceEntryId == sourceEntryId && 
            $0.sourceModule == sourceModule && 
            $0.destinationId == destinationId && 
            $0.destinationEntryId == destinationEntryId && 
            $0.destinationModule == destinationModule
        }
        let fetchDescriptor = FetchDescriptor<LinkDataModel>(predicate: predicate)
        
        if let existingLink = try? container.mainContext.fetch(fetchDescriptor).first {
            return existingLink.id
        }
        
        // Create new link if it doesn't exist
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
    
    func register(links: [LinkReplaceModel], destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules) -> [UUID] {
        var registeredIds: [UUID] = []
        var seenLinks: Set<String> = []
        
        for link in links {
            // Create a unique key for this link (excluding linkNumber for deduplication)
            let linkKey = "\(link.itemId)|\(link.entryId?.uuidString ?? "nil")|\(link.module.rawValue)|\(destinationId)|\(destinationEntryId?.uuidString ?? "nil")|\(destinationModule.rawValue)"
            
            // Only register if we haven't seen this exact link in this batch
            if !seenLinks.contains(linkKey) {
                seenLinks.insert(linkKey)
                let linkId = register(link: link, destinationId: destinationId, destinationEntryId: destinationEntryId, destinationModule: destinationModule)
                registeredIds.append(linkId)
            }
        }
        
        return registeredIds
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
