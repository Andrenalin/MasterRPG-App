// @copyright André Trettin

import CoreData
import Foundation
import os.log

@MainActor public struct LinkRegisterController: Sendable {
    public init(root: RootManager?) {
        self.root = root
        self.model = LinkRegisterListModel()
    }
    
    let root: RootManager?
    @MainActor public let model: LinkRegisterListModel
    
    @MainActor public func setup(context: NSManagedObjectContext?) {
        guard let context else { return }
        model.context = context
        
        Task.detached(priority: .userInitiated) {
            await context.perform {
                do {
                    let request: NSFetchRequest<NSFetchRequestResult> = LinkReferenceDataModel.fetchRequest()
                    guard let linkReferenceModels = try context.fetch(request) as? [LinkReferenceDataModel] else { return }
                    for linkReferenceModel in linkReferenceModels {
                        let source = ItemRowModel(itemId: linkReferenceModel.sourceId ?? UUID(), entryId: linkReferenceModel.sourceEntryId, typeId: NetworkModules(rawValue: Int(linkReferenceModel.sourceModule)) ?? .none)
                        let destination = ItemRowModel(itemId: linkReferenceModel.destinationId ?? UUID(), entryId: linkReferenceModel.destinationEntryId, typeId: NetworkModules(rawValue: Int(linkReferenceModel.destinationModule)) ?? .none)
                        
                        let newModel = LinkRegisterModel(name: linkReferenceModel.name ?? "", source: source, destination: destination)
                        
                        let keyId = destination.itemId
                        updateLink(keyId: keyId, addedModel: newModel)
                    }
                } catch {
                    Logger.coreDataController.error("tagdata error \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

public extension LinkRegisterController {
    @MainActor func isUsed(link: ItemRowModel) -> Bool {
        let keyId = link.itemId
        let used = !(model.items[keyId]?.isEmpty ?? true)
        return used
//        guard !used, link.entryId != nil else { return used }
//        return !(model.items[link.itemId]?.isEmpty ?? true)
    }
    
    @MainActor func resetUsedLink(for item: ItemRowModel) {
        let keyId = item.itemId
        var itemLinks = model.items[keyId, default: []]
        itemLinks.removeAll(where: { $0.destination == item })
    }

    @MainActor func used(for link: ItemRowModel) -> [EffectedItemModel] {
        let keyId = link.itemId
        let links = model.items[keyId, default: []]
        return links.map {
            guard let rootController = root?.itemRootController(for: $0.source.typeId), let item = rootController.itemControllable.itemSync(for: $0.source.itemId) else {
                return EffectedItemModel(id: $0.destination.itemId, name: "Module \($0.source.typeId) registered but item is gone", module: $0.source.typeId)
            }
            var entryName: String? = nil
            if let entryId = $0.source.entryId {
                entryName = item[entryId].name
            }
            return EffectedItemModel(id: UUID(), name: item.name, entryName: entryName, module: $0.source.typeId)
        }
    }
    
    @MainActor func repairLinks(for items: [ItemRowModel]) {
        for item in items {
            let keyId = item.itemId
            let links = model.items[keyId, default: []]
            for link in links {
                guard let linkController = root?.itemRootController(for: link.source.typeId)?.linkControllable else { continue }
                linkController.validateLinks(on: link.source.itemId)
            }
        }
    }
}

public extension LinkRegisterController {
    @MainActor func register(links: [LinkRegisterModel]) {
        for link in links {
            let keyId = link.destination.itemId
            updateLinkSync(keyId: keyId, addedModel: link)
        }
    }
    
    @MainActor func deregister(links: [LinkRegisterModel]) {
        for link in links {
            let keyId = link.destination.itemId
            updateLinkSync(keyId: keyId, removedModel: link)
        }
    }
}

private extension LinkRegisterController {
    nonisolated func updateLink(keyId: UUID, addedModel: LinkRegisterModel) {
        Task { @MainActor in
            var current = model.items[keyId, default: []]
            current.append(addedModel)
            model.items[keyId] = current
        }
    }

    @MainActor func updateLinkSync(keyId: UUID, addedModel: LinkRegisterModel) {
        var current = model.items[keyId, default: []]
        current.append(addedModel)
        model.items[keyId] = current
        updateDatabase(keyId: keyId, addedModel: addedModel)
    }

    @MainActor func updateLinkSync(keyId: UUID, removedModel: LinkRegisterModel) {
        var current = model.items[keyId, default: []]
        current.removeAll(where: { $0.source == removedModel.source && $0.destination == removedModel.destination })
        model.items[keyId] = current
        updateDatabase(keyId: keyId, removedModel: removedModel)
    }
    
    @MainActor func updateDatabase(keyId: UUID, removedModel: LinkRegisterModel) {
        guard let context = model.context else { return }
        Task.detached(priority: .userInitiated) {
            await context.perform {
                do {
                    let request: NSFetchRequest<NSFetchRequestResult> = LinkReferenceDataModel.fetchRequest()
                    if let sourceEntryId = removedModel.source.entryId, let destinationEntryId = removedModel.destination.entryId {
                        request.predicate = NSPredicate(format: "sourceId == %@ AND sourceEntryId == %@ AND destinationId == %@ AND destinationEntryId == %@", removedModel.source.itemId as CVarArg, sourceEntryId as CVarArg, removedModel.destination.itemId as CVarArg, destinationEntryId as CVarArg)
                    } else if let sourceEntryId = removedModel.source.entryId {
                        request.predicate = NSPredicate(format: "sourceId == %@ AND sourceEntryId == %@ AND destinationId == %@", removedModel.source.itemId as CVarArg, sourceEntryId as CVarArg, removedModel.destination.itemId as CVarArg)
                    } else if let destinationEntryId = removedModel.destination.entryId {
                        request.predicate = NSPredicate(format: "sourceId == %@ AND destinationId == %@ AND destinationEntryId == %@", removedModel.source.itemId as CVarArg, removedModel.destination.itemId as CVarArg, destinationEntryId as CVarArg)
                    } else {
                        request.predicate = NSPredicate(format: "sourceId == %@ AND destinationId == %@", removedModel.source.itemId as CVarArg, removedModel.destination.itemId as CVarArg)
                    }
                    
                    let removingModels = try context.fetch(request) as? [LinkReferenceDataModel]
                    for dbModel in removingModels ?? [] {
                        context.delete(dbModel)
                    }
                } catch {
                    Logger.coreDataController.error("tagdata error \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
    
    @MainActor func updateDatabase(keyId: UUID, addedModel: LinkRegisterModel) {
        guard let context = model.context else { return }
        Task.detached(priority: .userInitiated) {
            await context.perform {
                do {
                    let request: NSFetchRequest<NSFetchRequestResult> = LinkReferenceDataModel.fetchRequest()
                    if let sourceEntryId = addedModel.source.entryId, let destinationEntryId = addedModel.destination.entryId {
                        request.predicate = NSPredicate(format: "sourceId == %@ AND sourceEntryId == %@ AND destinationId == %@ AND destinationEntryId == %@", addedModel.source.itemId as CVarArg, sourceEntryId as CVarArg, addedModel.destination.itemId as CVarArg, destinationEntryId as CVarArg)
                    } else if let sourceEntryId = addedModel.source.entryId {
                        request.predicate = NSPredicate(format: "sourceId == %@ AND sourceEntryId == %@ AND destinationId == %@", addedModel.source.itemId as CVarArg, sourceEntryId as CVarArg, addedModel.destination.itemId as CVarArg)
                    } else if let destinationEntryId = addedModel.destination.entryId {
                        request.predicate = NSPredicate(format: "sourceId == %@ AND destinationId == %@ AND destinationEntryId == %@", addedModel.source.itemId as CVarArg, addedModel.destination.itemId as CVarArg, destinationEntryId as CVarArg)
                    } else {
                        request.predicate = NSPredicate(format: "sourceId == %@ AND destinationId == %@", addedModel.source.itemId as CVarArg, addedModel.destination.itemId as CVarArg)
                    }
                    
                    let alreadyAddedModels = try context.fetch(request) as? [LinkReferenceDataModel]
                    guard (alreadyAddedModels?.isEmpty ?? true) else { return }
                    
                    let dbModel = LinkReferenceDataModel(context: context)
                    dbModel.uuid = addedModel.id
                    dbModel.name = addedModel.name
                    dbModel.sourceId = addedModel.source.itemId
                    dbModel.sourceEntryId = addedModel.source.entryId
                    dbModel.sourceModule = Int16(addedModel.source.typeId.rawValue)
                    dbModel.destinationId = addedModel.destination.itemId
                    dbModel.destinationEntryId = addedModel.destination.entryId
                    dbModel.destinationModule = Int16(addedModel.destination.typeId.rawValue)
                } catch {
                    Logger.coreDataController.error("tagdata error \(error.localizedDescription, privacy: .public)")
                }
            }
        }
    }
}

// MARK: - Editor

public extension LinkRegisterController {
    @MainActor func linkRegisterModel(linkId: UUID) -> LinkRegisterModel? {
//        guard let (lookupId, isEntry) = model.links[linkId] else { return nil }
//        if isEntry {
//            return model.entries[lookupId, default: []].first(where: { $0.id == linkId} )
//        } else {
//            return model.items[lookupId, default: []].first(where: { $0.id == linkId} )
//        }
        return nil
    }

    @MainActor func linkRegisterModel(in text: String, for source: ItemRowModel) -> [LinkRegisterModel] {
//        let links = LinkReplaceController.links(for: text)
//        return links.map { rawLink -> LinkRegisterModel in
//            if let destinationEntryId = rawLink.entryId {
//                let entryLinks = model.entries[destinationEntryId, default: []]
//                if var linkRegisterModel = entryLinks.first(where: { $0.source.itemId == source.itemId && $0.source.entryId == source.entryId  }) {
//                    linkRegisterModel.markDown = rawLink.markDown
//                    return linkRegisterModel
//                }
//            } else {
//                let itemLinks = model.items[rawLink.itemId, default: []]
//                if var linkRegisterModel = itemLinks.first(where: { $0.source.itemId == source.itemId }) {
//                    linkRegisterModel.markDown = rawLink.markDown
//                    return linkRegisterModel
//                }
//            }
//            var newModel = LinkRegisterModel(name: rawLink.name, source: source, destination: ItemRowModel(itemId: rawLink.itemId, entryId: rawLink.entryId, typeId: rawLink.module))
//            register(links: [newModel])
//            newModel.markDown = rawLink.markDown
//            return newModel
//        }
        return []
    }
    
    func markDownLinkDataModel(for link: LinkRegisterModel) -> String {
        "[\(link.name)](\(URL.appScheme)://\(link.id))"
    }
}




//public extension LinkRegisterController {
//    func linkDataModel(linkId: UUID) -> LinkDataModel? {
////        let predicate = #Predicate<LinkDataModel> {
////            $0.id == linkId
////        }
////        let fetchDescription = FetchDescriptor<LinkDataModel>(predicate: predicate)
////        let models = try? container.mainContext.fetch(fetchDescription)
////        return models?.first
//        return nil
//    }
//    
//    func markDown(for link: LinkReferenceDataModel) -> String {
//        "[\(link.name)](\(URL.appScheme)://\(link.id))"
//    }
//
//    func linkDataModel(in text: String) -> [LinkReferenceDataModel] {
//        let links = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
//        return links.compactMap { rawLink -> LinkReferenceDataModel? in
//            linkDataModel(linkId: rawLink.linkId)
//        }
//    }
//    
//    /// Scans the given text for links of the form `[name](SCHEME://UUID/COMMAND)` and `[name](SCHEME://UUID)`, then fetches matching LinkDataModel rows by ID.
//    /// - Parameters:
//    ///   - text: The text to scan.
//    /// - Returns: All LinkDataModel instances whose `id` is referenced in the text.
//    func links(in text: String) -> [LinkReplaceModel] {
//        let links = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
//        return links.compactMap { rawLink -> LinkReplaceModel? in
//            guard let link = linkDataModel(linkId: rawLink.linkId) else { return nil }
//            let markDown = rawLink.markDown(for: URL.appScheme)
//            let range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
//            let command = rawLink.command
//            return LinkReplaceModel(name: rawLink.name, module: link.sourceModule, linkNumber: 0, itemId: link.sourceId, entryId: link.sourceEntryId, markDown: markDown, command: command, range: range)
//        }
//    }
//
//    func linksLong(in text: String) -> [LinkReplaceModel] {
//        let links = ReferenceScanner.allUuidUrls(for: URL.appScheme, in: text)
//        let result = links.tables.compactMap { rawLink -> LinkReplaceModel? in
//            let markDown = rawLink.markDown(for: URL.appScheme)
//            let range = text.range(of: markDown) ?? text.startIndex..<text.endIndex
//            return LinkReplaceModel(name: rawLink.name, module: NetworkModules.dice, linkNumber: 0, itemId: rawLink.table, entryId: nil, markDown: rawLink.markDown(for: URL.appScheme), command: rawLink.command, range: range)
//        }
//        return result
//    }
//
//    
//    func replaceLinks(in text: String, newItemId: UUID, newEntryId: UUID?) -> String {
//        let rawLinks = ReferenceScanner.parseUrlsUuid(for: URL.appScheme, in: text)
//        guard !rawLinks.isEmpty else { return text }
//        var resultText = text
//        for rawLink in rawLinks {
//            let markDown = rawLink.markDown(for: URL.appScheme)
//            guard let link = linkDataModel(linkId: rawLink.linkId) else {
//                resultText = resultText.replacingOccurrences(of: markDown, with: rawLink.name)
//                continue
//            }
//            let newLink = register(name: rawLink.name, sourceId: link.sourceId, sourceEntryId: link.sourceEntryId, sourceModule: link.sourceModule, destinationId: newItemId, destinationEntryId: newEntryId, destinationModule: link.destinationModule)
//            let newMarkDown = self.markDown(for: newLink)
//            resultText = resultText.replacingOccurrences(of: markDown, with: newMarkDown)
//        }
//        return resultText
//    }
//}
//
//public extension LinkRegisterController {
//    func register(link: LinkReplaceModel, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules) -> LinkReferenceDataModel {
//        let model = LinkDataModel(name: link.name, sourceId: link.itemId, sourceEntryId: link.entryId, sourceModule: link.module, destinationId: destinationId, destinationEntryId: destinationEntryId, destinationModel: destinationModule)
////        container.mainContext.insert(model)
////        try? container.mainContext.save()
//        return model
//    }
//    
//    func register(name: String = "", sourceId: UUID, sourceEntryId: UUID? = nil, sourceModule: NetworkModules, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModule: NetworkModules) -> LinkDataModel {
//        let model = LinkReferenceDataModel(
//            name: name,
//            sourceId: sourceId,
//            sourceEntryId: sourceEntryId,
//            sourceModule: sourceModule,
//            destinationId: destinationId,
//            destinationEntryId: destinationEntryId,
//            destinationModel: destinationModule
//        )
////        container.mainContext.insert(model)
////        try? container.mainContext.save()
//        return model
//    }
//    
//    func remove(linkId: UUID) {
//        guard let model = linkDataModel(linkId: linkId) else { return }
////        container.mainContext.delete(model)
////        try? container.mainContext.save()
//    }
//}
    
public extension LinkRegisterController {
    func effectedItems(targetId: UUID, targetEntryId: UUID? = nil, targetModule: NetworkModules) -> [EffectedItemModel] {
//        let predicate: Predicate<LinkDataModel>
//        if let targetEntryId {
//            predicate = #Predicate<LinkDataModel> {
//                $0.sourceId == targetId && $0.sourceEntryId == targetEntryId && $0.sourceModule == targetModule
//            }
//        } else {
//            predicate = #Predicate<LinkDataModel> {
//                $0.sourceId == targetId && $0.sourceModule == targetModule
//            }
//        }
//        let fetchDescription = FetchDescriptor<LinkDataModel>(predicate: predicate)
        return []
//        guard let models = try? container.mainContext.fetch(fetchDescription) else { return [] }
//
//        return models.map {
//            let item = itemControllable.itemSync(for: $0.destinationId)
//            return EffectedItemModel(id: $0.id, name: item?.name ?? $0.name, entryName: targetEntryId != nil ? $0.name : nil, module: $0.destinationModule)
//        }
    }
}
