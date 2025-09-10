// © André Trettin

import Foundation
import SwiftData

@MainActor
public struct LinkRegisterController {
    public  init(container: ModelContainer) {
        self.container = container
    }
    
    let container: ModelContainer
}

public extension LinkRegisterController {
    func register(link: LinkReplaceModel, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules) -> LinkDataModel {
        let model = LinkDataModel(name: link.name, sourceId: link.itemId, sourceEntryId: link.entryId, sourceModule: link.module, destinationId: destinationId, destinationEntryId: destinationEntryId, destinationModel: destinationModule)
        container.mainContext.insert(model)
        try? container.mainContext.save()
        return model
    }

    func register(name: String = "", sourceId: UUID, sourceEntryId: UUID? = nil, sourceModule: NetworkModules, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules) -> LinkDataModel {
        let model = LinkDataModel(
            name: name,
            sourceId: sourceId,
            sourceEntryId: sourceEntryId,
            sourceModule: sourceModule,
            destinationId: destinationId,
            destinationEntryId: destinationEntryId,
            destinationModel: destinationModule
        )
        container.mainContext.insert(model)
        try? container.mainContext.save()
        return model
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

public extension LinkRegisterController {
    /// Scans the given text for links of the form `[name](SCHEME://UUID)`, then fetches matching LinkDataModel rows by ID.
    /// - Parameters:
    ///   - text: The text to scan.
    /// - Returns: All LinkDataModel instances whose `id` is referenced in the text.
    func links(in text: String) -> [LinkReplaceModel] {
        // Extract UUIDs using the ReferenceScanner's UUID-only parser.
        let uuidLinks = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
        let ids = uuidLinks.map { $0.linkId }
        guard !ids.isEmpty else { return [] }
        
        // Build an OR predicate over all IDs.
        // If the set is large, consider chunking to keep predicate size manageable.
        let predicates: [Predicate<LinkDataModel>] = ids.map { linkId in
            #Predicate<LinkDataModel> { $0.id == linkId }
        }
        
        let combined: Predicate<LinkDataModel> = predicates.dropFirst().reduce(predicates.first!) { partial, next in
            #Predicate<LinkDataModel> { model in
                partial.evaluate(model) || next.evaluate(model)
            }
        }
        
        let fetch = FetchDescriptor<LinkDataModel>(predicate: combined)
        let linkModels = (try? container.mainContext.fetch(fetch)) ?? []
        return linkModels.map {
            let id = $0.id
            let markDown: String
            let range: Range<String.Index>
            let command: String?
            if let link = uuidLinks.first(where: { $0.linkId == id }) {
                markDown = link.markDown(for: URL.appScheme)
                range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
                command = link.command
            } else {
                markDown = self.markDown(for: $0)
                range = text.startIndex..<text.endIndex
                command = nil
            }
            return LinkReplaceModel(name: $0.name, module: $0.sourceModule, linkNumber: 0, itemId: $0.sourceId, entryId: $0.sourceEntryId, markDown: markDown, command: command, range: range)
        }
    }
    
    func markDown(for link: LinkDataModel) -> String {
        "[\(link.name)](\(URL.appScheme)://\(link.id))"
    }
}
