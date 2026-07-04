// @copyright André Trettin

import CoreData
import Foundation

/// A directional link from one item/entry to another, stored in the register keyed by `destination.itemId`.
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
    /// The item/entry that embeds the link (e.g. an AdventureEntry whose content text contains the markdown link).
    public let source: ItemRowModel
    /// The item/entry being referenced (used as the dictionary key in `LinkRegisterListModel.items`).
    public let destination: ItemRowModel
    /// Raw markdown string `[name](scheme://module/0/uuid[/entryId])` as it appears in the source text.
    public var markDown: String? = nil
    
    public func duplicate() -> LinkRegisterModel {
        LinkRegisterModel(name: name, source: source, destination: destination, markDown: markDown)
    }
    
    public var urlMarkDown: String {
        let entry = destination.entryId == nil ? "" : "/\(destination.entryId!.uuidString)"
        return "[\(name)](\(URL.appScheme)://\(destination.typeId.token)/0/\(destination.itemId.uuidString)\(entry))"
    }
}

/// Implemented by item models so `EditControllable.saveChanges` can diff which links were added or removed on each save.
@MainActor
public protocol ItemLinkRegistable {
    /// The item's unique identifier, used to locate existing register entries when resetting links.
    nonisolated var id: UUID { get }
    /// All links currently embedded in this item (used when no previous version exists, e.g. on first import).
    var linkRegisterModels: [LinkRegisterModel] { get }
    /// Returns the diff between `self` and `oldValue`; called on every save to register/deregister only what changed.
    func changedLinkRegisterModels(oldValue: Self) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel])
}

public extension ItemLinkRegistable {
    var linkRegisterModels: [LinkRegisterModel] { [] }
    func changedLinkRegisterModels(oldValue: Self) -> (added: [LinkRegisterModel], removed: [LinkRegisterModel]) { ([], []) }
}

/// In-memory store for all registered cross-module links. Keyed by `destination.itemId` → all links pointing to that destination.
@MainActor
public final class LinkRegisterListModel: Sendable {
    public init() {}

    var context: NSManagedObjectContext?

    /// Dictionary keyed by destination item UUID; each value is the list of `LinkRegisterModel`s pointing to that destination.
    public var items: [UUID: [LinkRegisterModel]] = [:]

    // Source item IDs whose links changed since the last savePendingLinks() call.
    // savePendingLinks() does a delete-and-replace for these source IDs from the current in-memory state.
    var pendingAffectedSourceIds: Set<UUID> = []
    
    func reset() {
        items = [:]
    }
    
    func setItem(itemId: UUID, with itemLinks: [LinkRegisterModel]) {
        items[itemId] = itemLinks
    }
}
