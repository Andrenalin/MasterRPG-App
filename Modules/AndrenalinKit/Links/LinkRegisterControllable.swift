// @copyright André Trettin

import Foundation

public struct LinkRegisterModel: Equatable, Hashable, Sendable {
    public init(source: ItemRowModel, destination: ItemRowModel) {
        self.source = source
        self.destination = destination
    }
    
    public let source: ItemRowModel
    public let destination: ItemRowModel
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
    
    func reset() {
        entries = [:]
        items = [:]
    }
    
    func setEntry(entryId: UUID, with entryLinks: [LinkRegisterModel]) {
        entries[entryId] = entryLinks
    }
    
    func setItem(itemId: UUID, with itemLinks: [LinkRegisterModel]) {
        items[itemId] = itemLinks
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

public struct EffectedItemModel: Equatable, Hashable, Identifiable, Sendable {
    public init(id: UUID, name: String, entryName: String? = nil, module: NetworkModules) {
        self.id = id
        self.name = name
        self.entryName = entryName
        self.module = module
    }
    
    public let id: UUID
    public let name: String
    public let entryName: String?
    public let module: NetworkModules
    
    var title: String {
        guard let entryName else {
            return name
        }
        return "\(name) --- \(entryName)"
    }
}

