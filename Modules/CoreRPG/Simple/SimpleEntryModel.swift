// @copyright André Trettin

import Foundation

/// A plain, freeform entry for ``SimpleModel``. Structurally identical to
/// every other module's `*EntryModel` (see `Modules/TableRPG/Model/TableEntryModel.swift`
/// for the shape this mirrors) but with no module-specific fields — a name
/// and a content string is all a throwaway, in-memory-only sheet entry
/// needs.
public struct SimpleEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
    public init(id: UUID = UUID(), childId: UUID = UUID(), name: String, content: String, displayState: Int = 0) {
        self.id = id
        self.childId = childId
        self.name = name
        self.content = content
        self.displayState = displayState
    }

    public var id: UUID
    public var childId: UUID
    public var name: String
    public var content: String
    public var displayState: Int
}

extension SimpleEntryModel: EntryDataAccessible {
    public static func newChild(id: UUID) -> Self {
        SimpleEntryModel(id: UUID(), childId: id, name: "", content: "")
    }

    public static var empty: SimpleEntryModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> SimpleEntryModel {
        SimpleEntryModel(id: id, name: "", content: "")
    }

    public func duplicate() -> SimpleEntryModel {
        SimpleEntryModel(id: UUID(), childId: childId, name: name, content: content, displayState: displayState)
    }
}

extension SimpleEntryModel: ItemDiffComparable {
    public func isSame(_ other: SimpleEntryModel) -> Bool {
        name == other.name && content == other.content
    }

    /// A `SimpleEntryModel` never syncs anywhere, so it never faces a real
    /// merge conflict to resolve — there is nothing to merge against.
    public func merge(_ other: SimpleEntryModel) -> SimpleEntryModel {
        self
    }
}

