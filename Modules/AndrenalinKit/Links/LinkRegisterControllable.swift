// @copyright André Trettin

import Foundation

public struct LinkRegisterModel: Equatable, Hashable, Sendable, Identifiable {
    public init(name: String, source: ItemRowModel, destination: ItemRowModel, markDown: String? = nil) {
        self.id = UUID()
        self.name = name
        self.source = source
        self.destination = destination
    }
    
    public let id: UUID
    public let name: String
    public let source: ItemRowModel
    public let destination: ItemRowModel
    public var markDown: String? = nil
    
    public func duplicate() -> LinkRegisterModel {
        LinkRegisterModel(name: name, source: source, destination: destination, markDown: markDown)
    }
}

public protocol ItemLinkRegistable {
    @MainActor var linkRegisterModels: [LinkRegisterModel] { get }
}

public extension ItemLinkRegistable {
    @MainActor
    var linkRegisterModels: [LinkRegisterModel] { [] }
}

@MainActor
public final class LinkRegisterListModel: Sendable {
    public init() {}
    
    public var items: [UUID: [LinkRegisterModel]] = [:]
    public var entries: [UUID: [LinkRegisterModel]] = [:]
    public var links: [UUID: (UUID, Bool)] = [:]
    
    func reset() {
        entries = [:]
        items = [:]
        links = [:]
    }
    
    func setEntry(entryId: UUID, with entryLinks: [LinkRegisterModel]) {
        let oldEntryLinks = entries[entryId, default: []]
        oldEntryLinks.forEach { links.removeValue(forKey: $0.id)}
        
        entries[entryId] = entryLinks
        entryLinks.forEach { links[$0.id] = (entryId, true) }
    }
    
    func setItem(itemId: UUID, with itemLinks: [LinkRegisterModel]) {
        let oldItemsLinks = items[itemId, default: []]
        oldItemsLinks.forEach { links.removeValue(forKey: $0.id) }

        items[itemId] = itemLinks
        itemLinks.forEach { links[$0.id] = (itemId, false) }
    }
}

public protocol LinkRegisterControllable: Sendable {
    @MainActor var model: LinkRegisterListModel { get }
    
    @MainActor func isUsed(link: ItemRowModel) -> Bool
    @MainActor func register(links: [LinkRegisterModel])
    @MainActor func deregister(links: [LinkRegisterModel])
    @MainActor func repairLinks(for items: [ItemRowModel])
    @MainActor func resetUsedLink(for item: ItemRowModel)
    @MainActor func used(for link: ItemRowModel) -> [EffectedItemModel]
    @MainActor func reset()
}

public extension LinkRegisterControllable {
    @MainActor
    func isUsed(link: ItemRowModel) -> Bool {
        let used = !(model.items[link.itemId]?.isEmpty ?? true)
        guard !used, let entryId = link.entryId else { return used }
        return !(model.entries[entryId]?.isEmpty ?? true)
    }
    
    @MainActor
    func register(links: [LinkRegisterModel]) {
        for link in links {
            if let entryId = link.destination.entryId {
                var entryLinks = model.entries[entryId, default: []]
                if !entryLinks.contains(where: { $0.source == link.source }) {
                    entryLinks.append(link)
                    model.setEntry(entryId: entryId, with: entryLinks)
                }
            }
            var itemLinks = model.items[link.destination.itemId, default: []]
            if !itemLinks.contains(where: { $0.source == link.source }) {
                itemLinks.append(link)
                model.setItem(itemId: link.destination.itemId, with: itemLinks)
            }
        }
    }

    @MainActor
    func deregister(links: [LinkRegisterModel]) {
        for link in links {
            if let entryId = link.destination.entryId {
                var entryLinks = model.entries[entryId, default: []]
                if let index = entryLinks.firstIndex(where: { $0.source == link.source }) {
                    entryLinks.remove(at: index)
                    model.setEntry(entryId: entryId, with: entryLinks)
                }
            }
            var itemLinks = model.items[link.destination.itemId, default: []]
            if let index = itemLinks.firstIndex(where: { $0.source == link.source }) {
                itemLinks.remove(at: index)
                model.setItem(itemId: link.destination.itemId, with: itemLinks)
            }
        }
    }

    @MainActor
    func reset() {
        model.reset()
    }
    
    @MainActor
    func resetUsedLink(for item: ItemRowModel) {
        if let entryId = item.entryId {
            var entryLinks = model.entries[entryId, default: []]
            entryLinks.removeAll(where: { $0.destination == item })
            model.setEntry(entryId: entryId, with: entryLinks)
        }
        var itemLinks = model.items[item.itemId, default: []]
        itemLinks.removeAll { $0.destination.itemId == item.itemId }
        model.setItem(itemId: item.itemId, with: itemLinks)
    }
}

// MARK: - Editor

public extension LinkRegisterControllable {
    @MainActor func linkRegisterModel(linkId: UUID) -> LinkRegisterModel? {
        guard let (lookupId, isEntry) = model.links[linkId] else { return nil }
        if isEntry {
            return model.entries[lookupId, default: []].first(where: { $0.id == linkId} )
        } else {
            return model.items[lookupId, default: []].first(where: { $0.id == linkId} )
        }
    }

    @MainActor func linkRegisterModel(in text: String, for source: ItemRowModel) -> [LinkRegisterModel] {
        let links = LinkReplaceController.links(for: text)
        return links.map { rawLink -> LinkRegisterModel in
            if let destinationEntryId = rawLink.entryId {
                let entryLinks = model.entries[destinationEntryId, default: []]
                if var linkRegisterModel = entryLinks.first(where: { $0.source.itemId == source.itemId && $0.source.entryId == source.entryId  }) {
                    linkRegisterModel.markDown = rawLink.markDown
                    return linkRegisterModel
                }
            } else {
                let itemLinks = model.items[rawLink.itemId, default: []]
                if var linkRegisterModel = itemLinks.first(where: { $0.source.itemId == source.itemId }) {
                    linkRegisterModel.markDown = rawLink.markDown
                    return linkRegisterModel
                }
            }
            var newModel = LinkRegisterModel(name: rawLink.name, source: source, destination: ItemRowModel(itemId: rawLink.itemId, entryId: rawLink.entryId, typeId: rawLink.module))
            register(links: [newModel])
            newModel.markDown = rawLink.markDown
            return newModel
        }
    }
    
    func markDownLinkDataModel(for link: LinkRegisterModel) -> String {
        "[\(link.name)](\(URL.appScheme)://\(link.id))"
    }
}
