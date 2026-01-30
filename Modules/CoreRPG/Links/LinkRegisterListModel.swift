// @copyright André Trettin

import CoreData
import Foundation

public struct LinkRegisterModel: Equatable, Hashable, Sendable, Identifiable {
    public init(name: String, source: ItemRowModel, destination: ItemRowModel, markDown: String? = nil) {
        self.id = UUID()
        self.name = name
        self.source = source
        self.destination = destination
        self.markDown = markDown
    }
    
    public let id: UUID
    public let name: String
    public let source: ItemRowModel
    public let destination: ItemRowModel
    public var markDown: String? = nil
    
    public func duplicate() -> LinkRegisterModel {
        LinkRegisterModel(name: name, source: source, destination: destination, markDown: markDown)
    }
    
    public var urlMarkDown: String {
        let entry = destination.entryId == nil ? "" : "/\(destination.entryId!.uuidString)"
        return "[\(name)](\(URL.appScheme)://\(destination.typeId.token)/0/\(destination.itemId.uuidString)\(entry))"
    }
}

public protocol ItemLinkRegistable {
    @MainActor var linkRegisterModels: [LinkRegisterModel] { get }
    @MainActor func changedLinkRegisterModels(oldValue: Self) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel])
}

public extension ItemLinkRegistable {
    @MainActor var linkRegisterModels: [LinkRegisterModel] { [] }
    @MainActor func changedLinkRegisterModels(oldValue: Self) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) { ([], []) }
}

@MainActor
public final class LinkRegisterListModel: Sendable {
    public init() {}
    
    var context: NSManagedObjectContext?
    
    public var items: [UUID: [LinkRegisterModel]] = [:]
//    public var entries: [UUID: [LinkRegisterModel]] = [:]
//    public var links: [UUID: (UUID, Bool)] = [:]
    
    func reset() {
//        entries = [:]
        items = [:]
//        links = [:]
    }
    
//    func setEntry(entryId: UUID, with entryLinks: [LinkRegisterModel]) {
//        let oldEntryLinks = entries[entryId, default: []]
//        oldEntryLinks.forEach { links.removeValue(forKey: $0.id)}
//        
//        entries[entryId] = entryLinks
//        entryLinks.forEach { links[$0.id] = (entryId, true) }
//    }
    
    func setItem(itemId: UUID, with itemLinks: [LinkRegisterModel]) {
        //let oldItemsLinks = items[itemId, default: []]
        //oldItemsLinks.forEach { links.removeValue(forKey: $0.id) }

        items[itemId] = itemLinks
        //itemLinks.forEach { links[$0.id] = (itemId, false) }
    }
}
