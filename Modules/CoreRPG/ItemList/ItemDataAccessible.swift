// @copyright André Trettin

import Foundation
import SwiftUI

/// A model property value for the import review. Non-string types (toggles, enums,
/// numbers) provide a string representation used for rendering and change detection.
public enum ReviewPropertyValue: Equatable, Sendable {
    case text(String)
    case toggle(Bool)
    case number(Double)
    case option(String)
    /// A linked item (e.g. photoId / diceId) — rendered with the destination module's thumbnail.
    case link(ItemRowModel?)

    public var displayText: String {
        switch self {
        case .text(let value): value
        case .toggle(let value): value ? String(localized: "On", bundle: .module) : String(localized: "Off", bundle: .module)
        case .number(let value): value.formatted(.number)
        case .option(let value): value
        case .link(let value): value?.itemId.uuidString ?? ""
        }
    }
}

public extension ReviewPropertyValue {
    init(_ value: String) { self = .text(value) }
    init(_ value: Bool) { self = .toggle(value) }
    init(_ value: some BinaryInteger) { self = .number(Double(value)) }
    init(_ value: some BinaryFloatingPoint) { self = .number(Double(value)) }
    /// Enums with a String raw value render their raw value.
    init(_ value: some RawRepresentable<String>) { self = .option(value.rawValue) }
    init(photoId: UUID?) { self = .link(photoId.map { ItemRowModel(itemId: $0, typeId: .photo) }) }
    init(diceId: UUID?) { self = .link(diceId.map { ItemRowModel(itemId: $0, typeId: .dice) }) }
}

/// Describes one custom model property shown in the import review in addition to the
/// standard name / description / tags / file rows. Read-only: the review displays the
/// value per model version; the value itself follows the chosen version on apply.
public struct ReviewCustomProperty: Sendable {
    public init(
        displayName: String,
        value: @escaping @MainActor (any ItemDataAccessible) -> ReviewPropertyValue
    ) {
        self.displayName = displayName
        self.value = value
    }

    public let displayName: String
    /// Reads the property from one model version (existing, imported or merged).
    public let value: @MainActor (any ItemDataAccessible) -> ReviewPropertyValue
}

// Model state is MainActor-owned. Only `id` and the static factories stay
// nonisolated because they are immutable/static identity APIs used by generic
// infrastructure such as Identifiable, decoding, and empty model factories.
@MainActor
public protocol ItemDataAccessible: Sendable, Equatable {
    associatedtype Entry: EntryDataAccessible, Identifiable, Equatable

    nonisolated static var empty: Self { get }
    nonisolated static var typeId: NetworkModules { get }
    nonisolated static func empty(_ id: UUID) -> Self

    nonisolated var id: UUID { get }
    var name: String { get set }
    var category: ItemListCategory { get set }
    var description: String { get set }
    var tags: [String] { get set }
    var displayState: Int { get set }
    var isGroupHidden: Bool { get }
    var isGroupHiddenToggle: Bool { get set }
    var entries: [Entry] { get nonmutating set }
    var fileUrl: FileUrl? { get set }
    var parentId: UUID? { get set }

    subscript(id: UUID) -> Entry { get set }

    func urlAdr(linkNumber: Int) -> String
    func urlAdr(linkNumber: Int, entryId: UUID) -> String
    func urlName() -> String
    func urlName(entryId: UUID) -> String
    func url(linkNumber: Int) -> String
    func url(linkNumber: Int, entryId: UUID) -> String

    func copy() -> Self
    func duplicate() -> Self
    func filter(filter: String, includeEntries: Bool) -> Bool
    func isEqual(other: Self) -> Bool
    func replace(with model: Self) -> Bool

    /// Custom model properties shown in the import review in addition to the standard ones.
    var reviewProperties: [ReviewCustomProperty] { get }

    /// Applies to `self` (the library copy) the module's own properties that `edited` changed
    /// relative to `base` (the game copy a forced editor save started from), as `applyEdit`
    /// does for the properties every item has. Leave out what is session-only during a game
    /// (a map's pins and rooms). The default applies nothing.
    @MainActor mutating func applyModuleEdit(from base: Self, to edited: Self)

    /// `applyModuleEdit` including what is session-only during a game: undo and redo of an edit
    /// that was written where it was made (game memory, or the library outside a game) revert
    /// all of it. The default is `applyModuleEdit`. See CODE_AUDIT_Edit_Save §5.2.
    @MainActor mutating func applyModuleUndo(from base: Self, to edited: Self)

    /// Whether the entries (with everything `applyModuleEdit` leaves out) are content that stays
    /// in game memory while a game runs, also when the editor window saves with `forceSave`:
    /// a forced save then persists only the item's metadata. A map's rooms are; the decision is
    /// enforced in `EditControllable.writeForcedEditOfGameCopy` instead of in every map edit.
    /// See CODE_AUDIT_Edit_Save §5.13.
    nonisolated static var hasSessionOnlyEntries: Bool { get }
}

public extension ItemDataAccessible {
    /// Type-erased content equality for `any ItemDataAccessible` existentials.
    ///
    /// `isEqual(other:)` requires `Self`, so two existential boxes can't be compared with it
    /// directly — this opens `self`'s concrete type via a dynamic cast of `other` instead.
    /// Lets SwiftUI-facing wrapper types (e.g. row views holding `any ItemDataAccessible`)
    /// build an `Equatable` render snapshot without hand-picking individual fields. See
    /// CODE_AUDIT §8.4.
    func isEqualErased(to other: any ItemDataAccessible) -> Bool {
        guard let other = other as? Self else { return false }
        return isEqual(other: other)
    }

    var reviewProperties: [ReviewCustomProperty] { [] }
    @MainActor mutating func applyModuleEdit(from base: Self, to edited: Self) {}
    @MainActor mutating func applyModuleUndo(from base: Self, to edited: Self) {
        applyModuleEdit(from: base, to: edited)
    }
    nonisolated static var hasSessionOnlyEntries: Bool { false }
    var url: URL? {
        fileUrl?.rawUrl
    }

    var fileUrl: FileUrl? {
        nil
    }

    var isFolder: Bool {
        category == .folder
    }

    var specialCategory: Bool {
        category == .folder || category.isCollection
    }

    func hasEntry(entryId: UUID) -> Bool {
        entries.contains(where: { $0.childId == entryId })
    }

    func urlAdr(linkNumber: Int) -> String {
        LinkBuilder.address(module: Self.typeId, linkNumber: linkNumber, itemId: id)
    }

    func urlAdr(linkNumber: Int, entryId: UUID) -> String {
        "\(urlAdr(linkNumber: linkNumber))/\(entryId)"
    }

    func urlName() -> String {
        name.withoutLink()
    }

    func urlName(entryId: UUID) -> String {
        self[entryId].name.withoutLink()
    }

    func url(linkNumber: Int) -> String {
        "[\(LinkBuilder.escapedLabel(urlName()))](\(urlAdr(linkNumber: linkNumber)))"
    }

    func url(linkNumber: Int, entryId: UUID) -> String {
        "[\(LinkBuilder.escapedLabel(urlName(entryId: entryId)))](\(urlAdr(linkNumber: linkNumber, entryId: entryId)))"
    }
}
