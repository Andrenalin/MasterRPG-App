// @copyright André Trettin

import Foundation
import Observation

/// A plain, freeform in-memory item for ``SimpleSheetEditingSession``. Has
/// the same shape as every module's own domain model (see
/// `Modules/TableRPG/Model/TableModel.swift`) but with plain stored
/// properties instead of `CRDT<T>` wrappers — a `SimpleModel` never syncs to
/// Core Data/CloudKit, so it has nothing to reconcile a CRDT merge against.
///
/// Unlike `Modules/CoreRPG/Fake/FakeItemModel.swift` (a display-only preview
/// fixture whose `replace(with:)`/`isSame`/`==` are all stubbed to do
/// nothing), every mutating/comparison method here is real: `SheetRootModel`
/// editing sessions built on this type actually apply and reflect edits.
@MainActor @Observable
public final class SimpleModel: nonisolated Identifiable {
    nonisolated public init(
        id: UUID = UUID(),
        name: String = "",
        category: ItemListCategory = .item,
        description: String = "",
        tags: [String] = [],
        displayState: Int = 0,
        isGroupHiddenToggle: Bool = false,
        entries: [SimpleEntryModel] = [],
        parentId: UUID? = nil
    ) {
        // Direct assignment to the `@Observable` macro's synthesized backing
        // storage (`_name`, not the tracked `name` computed accessor) — the
        // same escape hatch `Modules/TableRPG/Model/TableModel.swift`'s own
        // `nonisolated init` uses (there via its manually named `_name_`
        // CRDT-backed property) to initialize a MainActor-isolated stored
        // property from a nonisolated context. Required because
        // `ItemDataAccessible.empty(_:)` is a `nonisolated static`
        // requirement that must construct a `SimpleModel` synchronously.
        self.id = id
        self._name = name
        self._category = category
        self._description = description
        self._tags = tags
        self._displayState = displayState
        self._isGroupHiddenToggle = isGroupHiddenToggle
        self._entries = entries
        self._parentId = parentId
    }

    nonisolated public let id: UUID
    public var name: String
    public var category: ItemListCategory
    public var description: String
    public var tags: [String]
    public var displayState: Int
    public var isGroupHiddenToggle: Bool
    public var entries: [SimpleEntryModel]
    public var parentId: UUID?

    private enum CodingKeys: CodingKey {
        case id, name, category, description, tags, displayState, isGroupHiddenToggle, entries, parentId
    }

    nonisolated public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try container.decode(UUID.self, forKey: .id)
        self._name = try container.decode(String.self, forKey: .name)
        self._category = try container.decode(ItemListCategory.self, forKey: .category)
        self._description = try container.decode(String.self, forKey: .description)
        self._tags = try container.decode([String].self, forKey: .tags)
        self._displayState = try container.decode(Int.self, forKey: .displayState)
        self._isGroupHiddenToggle = try container.decode(Bool.self, forKey: .isGroupHiddenToggle)
        self._entries = try container.decode([SimpleEntryModel].self, forKey: .entries)
        self._parentId = try container.decodeIfPresent(UUID.self, forKey: .parentId)
    }

    nonisolated public final func encode(to encoder: any Encoder) throws {
        try encoder.encodeOnMainActor { encoder in
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(self.id, forKey: .id)
            try container.encode(self.name, forKey: .name)
            try container.encode(self.category, forKey: .category)
            try container.encode(self.description, forKey: .description)
            try container.encode(self.tags, forKey: .tags)
            try container.encode(self.displayState, forKey: .displayState)
            try container.encode(self.isGroupHiddenToggle, forKey: .isGroupHiddenToggle)
            try container.encode(self.entries, forKey: .entries)
            try container.encodeIfPresent(self.parentId, forKey: .parentId)
        }
    }
}

extension SimpleModel: nonisolated ItemDataAccessible {
    public var fileUrl: FileUrl? {
        get { nil }
        set {}
    }

    nonisolated public static var empty: SimpleModel { empty(UUID()) }
    nonisolated public static func empty(_ id: UUID) -> SimpleModel {
        SimpleModel(id: id, name: "")
    }
    nonisolated public static let typeId: NetworkModules = .none

    public func copy() -> SimpleModel {
        SimpleModel(id: id, name: name, category: category, description: description, tags: tags, displayState: displayState, isGroupHiddenToggle: isGroupHiddenToggle, entries: entries, parentId: parentId)
    }

    public func filter(filter: String, includeEntries: Bool) -> Bool {
        guard !filter.isEmpty else { return true }
        guard !(name.localizedStandardContains(filter) || description.localizedStandardContains(filter)) else { return true }
        return entries.contains { $0.filter(with: filter) }
    }

    public func isEqual(other: SimpleModel) -> Bool {
        self == other
    }

    /// Applies every field from `model` and reports whether anything
    /// actually changed — this is what `ItemControllable.replace(...)` calls
    /// to commit an edit, so it must be a real assignment (not a stub).
    public func replace(with model: SimpleModel) -> Bool {
        guard self != model else { return false }
        name = model.name
        category = model.category
        description = model.description
        tags = model.tags
        displayState = model.displayState
        isGroupHiddenToggle = model.isGroupHiddenToggle
        entries = model.entries
        parentId = model.parentId
        return true
    }

    public subscript(id: UUID) -> SimpleEntryModel {
        get {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return .empty(id) }
            return entries[index]
        }
        set {
            guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
            entries[index] = newValue
        }
    }
}

extension SimpleModel: nonisolated ItemDiffComparable {
    public func isSame(_ other: SimpleModel) -> Bool {
        name == other.name
            && category == other.category
            && description == other.description
            && tags == other.tags
            && displayState == other.displayState
            && entries == other.entries
            && parentId == other.parentId
    }

    /// A `SimpleModel` never syncs anywhere, so it never faces a real merge
    /// conflict to resolve — there is nothing to merge against.
    public func merge(_ other: SimpleModel) -> SimpleModel {
        self
    }
}

extension SimpleModel: nonisolated ItemDuplicatable {
    public func duplicate() -> SimpleModel {
        SimpleModel(id: UUID(), name: duplicateName(from: name), category: category, description: description, tags: tags, displayState: displayState, isGroupHiddenToggle: isGroupHiddenToggle, entries: entries.map { $0.duplicate() }, parentId: nil)
    }
}

// `ItemLinkRegistrable`'s requirements both have `[]`/`([], [])` extension
// defaults — a `SimpleModel` never registers cross-item links, so the
// defaults are the correct behavior here, not a stub.
extension SimpleModel: nonisolated ItemLinkRegistrable {}

extension SimpleModel: nonisolated Equatable, nonisolated Hashable, nonisolated Codable {
    nonisolated public static func == (lhs: SimpleModel, rhs: SimpleModel) -> Bool {
        assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState
        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
