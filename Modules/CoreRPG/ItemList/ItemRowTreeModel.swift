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

    @MainActor
    public required init(from decoder: Decoder) throws {
        let container: KeyedDecodingContainer<ItemRowTreeModel.CodingKeys> = try decoder.container(keyedBy: ItemRowTreeModel.CodingKeys.self)

        self.id = try container.decode(UUID.self, forKey: ItemRowTreeModel.CodingKeys.id)
        self.model = try container.decode(ItemRowModel.self, forKey: ItemRowTreeModel.CodingKeys.model)
        self.level = try container.decode(Int.self, forKey: ItemRowTreeModel.CodingKeys.level)
        self._expanded = try container.decode(Bool.self, forKey: ItemRowTreeModel.CodingKeys._expanded)
        self._children = try container.decode([ItemRowTreeModel].self, forKey: ItemRowTreeModel.CodingKeys._children)
        self._idChildren = try container.decode([UUID : Int].self, forKey: ItemRowTreeModel.CodingKeys._idChildren)
    }

    public static let empty: ItemRowTreeModel = .init(id: UUID(), model: ItemRowModel.empty)

    public var selectionId: String {
        "S-\(id.uuidString)"
    }
}

// Isolated conformances (SE-0470): usable only on the main actor, checked at compile time
// instead of trapping at runtime. See CODE_AUDIT_19 §4.1.
extension ItemRowTreeModel: @MainActor Codable {
    enum CodingKeys: CodingKey {
        case id
        case model
        case level
        case _expanded
        case _children
        case _idChildren
    }

    public func encode(to encoder: Encoder) throws {
        var container: KeyedEncodingContainer<ItemRowTreeModel.CodingKeys> = encoder.container(keyedBy: ItemRowTreeModel.CodingKeys.self)

        try container.encode(self.id, forKey: ItemRowTreeModel.CodingKeys.id)
        try container.encode(self.model, forKey: ItemRowTreeModel.CodingKeys.model)
        try container.encode(self.level, forKey: ItemRowTreeModel.CodingKeys.level)
        try container.encode(self._expanded, forKey: ItemRowTreeModel.CodingKeys._expanded)
        try container.encode(self._children, forKey: ItemRowTreeModel.CodingKeys._children)
        try container.encode(self._idChildren, forKey: ItemRowTreeModel.CodingKeys._idChildren)
    }
}

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
