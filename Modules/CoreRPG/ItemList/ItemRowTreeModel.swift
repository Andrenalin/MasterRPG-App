// @copyright André Trettin

import SwiftUI

@MainActor @Observable
public final class ItemRowTreeModel: Identifiable, Sendable {
    public let id: UUID
    public let model: ItemRowModel
    public let level: Int
    public var expanded: Bool = false
    public var children: [ItemRowTreeModel] = []
    public var idChildren: [UUID: Int] = [:]

    public init(id: UUID, model: ItemRowModel, level: Int = 0, expanded: Bool = false, children: [ItemRowTreeModel] = [], idChildren: [UUID: Int] = [:]) {
        self.id = id
        self.model = model
        self.level = level
        self.expanded = expanded
        self.children = children
        self.idChildren = idChildren
    }

    public init(itemId: UUID, entryId: UUID? = nil, typeId: NetworkModules) {
        self.id = UUID()
        self.model = ItemRowModel(itemId: itemId, entryId: entryId, typeId: typeId)
        self.level = 0
    }

    public static let empty: ItemRowTreeModel = .init(id: UUID(), model: ItemRowModel.empty)

    public var selectionId: String {
        "S-\(id.uuidString)"
    }
}

// Isolated conformances (SE-0470): usable only on the main actor, checked at compile time
// instead of trapping at runtime. See CODE_AUDIT_19 §4.1. The hand-written `Codable` was
// removed: nothing encodes or decodes a tree model. See CODE_AUDIT_20 §9.11.
extension ItemRowTreeModel: @MainActor Equatable, @MainActor Hashable {
    public static func == (lhs: ItemRowTreeModel, rhs: ItemRowTreeModel) -> Bool {
        lhs.id == rhs.id &&
        lhs.expanded == rhs.expanded &&
        lhs.level == rhs.level &&
        lhs.model == rhs.model
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}

public struct ItemRowModel: Equatable, Hashable, Codable, Sendable {
    public init(itemId: UUID, entryId: UUID? = nil, typeId: NetworkModules) {
        self.itemId = itemId
        self.entryId = entryId
        self.typeId = typeId
    }

    public let itemId: UUID
    public let entryId: UUID?
    public let typeId: NetworkModules

    static let empty = ItemRowModel(itemId: UUID(), entryId: nil, typeId: .none)
}
