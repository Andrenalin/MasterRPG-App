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
    func linkDataModel(linkId: UUID) -> LinkDataModel? {
        let predicate = #Predicate<LinkDataModel> {
            $0.id == linkId
        }
        let fetchDescription = FetchDescriptor<LinkDataModel>(predicate: predicate)
        let models = try? container.mainContext.fetch(fetchDescription)
        return models?.first
    }
    
    func markDown(for link: LinkDataModel) -> String {
        "[\(link.name)](\(URL.appScheme)://\(link.id))"
    }

    func linkDataModel(in text: String) -> [LinkDataModel] {
        let links = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
        return links.compactMap { rawLink -> LinkDataModel? in
            linkDataModel(linkId: rawLink.linkId)
        }
    }

    /// Scans the given text for links of the form `[name](SCHEME://UUID/COMMAND)` and `[name](SCHEME://UUID)`, then fetches matching LinkDataModel rows by ID.
    /// - Parameters:
    ///   - text: The text to scan.
    /// - Returns: All LinkDataModel instances whose `id` is referenced in the text.
    func links(in text: String) -> [LinkReplaceModel] {
        let links = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
        return links.compactMap { rawLink -> LinkReplaceModel? in
            guard let link = linkDataModel(linkId: rawLink.linkId) else { return nil }
            let markDown = rawLink.markDown(for: URL.appScheme)
            let range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
            let command = rawLink.command
            return LinkReplaceModel(name: rawLink.name, module: link.sourceModule, linkNumber: 0, itemId: link.sourceId, entryId: link.sourceEntryId, markDown: markDown, command: command, range: range)
        }
    }

    func verifyLinks(in text: String, destinationItemId: UUID, destinationEntryId: UUID?, destinationModule: NetworkModules) -> String {
        let rawLinks = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
        guard !rawLinks.isEmpty else { return text }
        var resultText = text
        for rawLink in rawLinks {
        }
        return resultText
    }

    func replaceLinks(in text: String, newItemId: UUID, newEntryId: UUID?) -> String {
        let rawLinks = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
        guard !rawLinks.isEmpty else { return text }
        var resultText = text
        for rawLink in rawLinks {
            let markDown = rawLink.markDown(for: URL.appScheme)
            guard let link = linkDataModel(linkId: rawLink.linkId) else {
                resultText = resultText.replacingOccurrences(of: markDown, with: rawLink.name)
                continue
            }
            let newLink = register(name: rawLink.name, sourceId: link.sourceId, sourceEntryId: link.sourceEntryId, sourceModule: link.sourceModule, destinationId: newItemId, destinationEntryId: newEntryId, destinationModule: link.destinationModule)
            let newMarkDown = self.markDown(for: newLink)
            resultText = resultText.replacingOccurrences(of: markDown, with: newMarkDown)
        }
        return resultText
    }
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
        guard let model = linkDataModel(linkId: linkId) else { return }
        container.mainContext.delete(model)
        try? container.mainContext.save()
    }
}
    
public extension LinkRegisterController {
    func effectedItems(targetId: UUID, targetEntryId: UUID? = nil, targetModule: NetworkModules) -> [EffectedItemModel] {
        let predicate: Predicate<LinkDataModel>
        if let targetEntryId {
            predicate = #Predicate<LinkDataModel> {
                $0.sourceId == targetId && $0.sourceEntryId == targetEntryId && $0.sourceModule == targetModule
            }
        } else {
            predicate = #Predicate<LinkDataModel> {
                $0.sourceId == targetId && $0.sourceModule == targetModule
            }
        }
        let fetchDescription = FetchDescriptor<LinkDataModel>(predicate: predicate)
        guard let models = try? container.mainContext.fetch(fetchDescription) else { return [] }
        
        return models.map {
            let item = ItemDataModel.model(modelContext: ModelContext(container), id: $0.destinationId)
            return EffectedItemModel(id: $0.id, name: item?.name ?? $0.name, entryName: targetEntryId != nil ? $0.name : nil, module: $0.destinationModule)
        }
    }
}

