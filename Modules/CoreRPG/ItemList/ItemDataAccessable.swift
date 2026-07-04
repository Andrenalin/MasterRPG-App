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
        value: @escaping @MainActor (any ItemDataAccessable) -> ReviewPropertyValue
    ) {
        self.displayName = displayName
        self.value = value
    }

    public let displayName: String
    /// Reads the property from one model version (existing, imported or merged).
    public let value: @MainActor (any ItemDataAccessable) -> ReviewPropertyValue
}

// Model state is MainActor-owned: all content requirements are @MainActor so that
// @MainActor domain models can conform without escape hatches. Nonisolated models
// (not yet migrated) satisfy isolated requirements trivially. Only `id` and the
// static factories stay nonisolated — they must be callable from nonisolated
// generic code (Identifiable, decode) and are backed by immutable/Sendable state.
public protocol ItemDataAccessable: Sendable, Equatable {
    associatedtype Entry: EntryDataAccessable, Identifiable, Equatable

    static var empty: Self { get }
    static var typeId: NetworkModules { get }
    static func empty(_ id: UUID) -> Self

    var id: UUID { get }
    @MainActor var name: String { get set }
    @MainActor var category: ItemListCategory { get set }
    @MainActor var description: String { get set }
    @MainActor var tags: [String] { get set }
    @MainActor var displayState: Int { get set }
    @MainActor var isGroupHidden: Bool { get }
    @MainActor var isGroupHiddenToggle: Bool { get set }
    @MainActor var entries: [Entry] { get nonmutating set }
    @MainActor var fileUrl: FileUrl? { get set }
    @MainActor var parentId: UUID? { get set }

    @MainActor subscript(id: UUID) -> Entry { get set }

    @MainActor func urlAdr(linkNumber: Int) -> String
    @MainActor func urlAdr(linkNumber: Int, entryId: UUID) -> String
    @MainActor func urlName() -> String
    @MainActor func urlName(entryId: UUID) -> String
    @MainActor func url(linkNumber: Int) -> String
    @MainActor func url(linkNumber: Int, entryId: UUID) -> String

    @MainActor func copy() -> Self
    @MainActor func duplicate() -> Self
    @MainActor func filter(filter: String, includeEntries: Bool) -> Bool
    @MainActor func isEqual(other: Self) -> Bool
    @MainActor func replace(with model: Self) -> Bool

    /// Custom model properties shown in the import review in addition to the standard ones.
    @MainActor var reviewProperties: [ReviewCustomProperty] { get }
}

public extension ItemDataAccessable {
    @MainActor var reviewProperties: [ReviewCustomProperty] { [] }
    @MainActor var url: URL? {
        fileUrl?.rawUrl
    }

    @MainActor var fileUrl: FileUrl? {
        nil
    }

    @MainActor var isFolder: Bool {
        category == .folder
    }

    @MainActor var specialCategory: Bool {
        category == .folder || category.isCollection
    }

    @MainActor func hasEntry(entryId: UUID) -> Bool {
        entries.contains(where: { $0.childId == entryId })
    }

    @MainActor func urlAdr(linkNumber: Int) -> String {
        "\(URL.appScheme)://\(Self.typeId.token)/\(linkNumber)/\(id)"
    }

    @MainActor func urlAdr(linkNumber: Int, entryId: UUID) -> String {
        "\(urlAdr(linkNumber: linkNumber))/\(entryId)"
    }

    @MainActor func urlName() -> String {
        name.withoutLink()
    }

    @MainActor func urlName(entryId: UUID) -> String {
        self[entryId].name.withoutLink()
    }

    @MainActor func url(linkNumber: Int) -> String {
        "[\(urlName())](\(urlAdr(linkNumber: linkNumber)))"
    }

    @MainActor func url(linkNumber: Int, entryId: UUID) -> String {
        "[\(urlName(entryId: entryId))](\(urlAdr(linkNumber: linkNumber, entryId: entryId)))"
    }
}
