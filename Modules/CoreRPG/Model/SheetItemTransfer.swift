// @copyright André Trettin

import Foundation

/// A Codable, network-transferable snapshot of the wrapper/nested-rows shape
/// `EditControllable.addItem(sheet:forceSave:)` reads off a live, in-memory-only
/// `SheetModel` — the same shape `TableGenerationController.addOutcomeToCharacter(session:)`
/// already hands it for the local Save path. `init(sheet:)`/`makeSheetModel()`
/// mirror `addItem(sheet:forceSave:)`'s own extraction exactly, so encoding
/// for Send and reading for Save can never drift apart.
public struct SheetItemTransfer: Identifiable, Equatable, Codable, Sendable, MessageMapper {
    public struct Entry: Equatable, Codable, Sendable {
        public init(name: String, content: String) {
            self.name = name
            self.content = content
        }

        public let name: String
        public let content: String
    }

    public init(id: UUID = UUID(), name: String, description: String, entries: [Entry]) {
        self.id = id
        self.name = name
        self.description = description
        self.entries = entries
    }

    public let id: UUID
    public let name: String
    public let description: String
    public let entries: [Entry]
}

public extension SheetItemTransfer {
    /// Reads the exact same shape `addItem(sheet:forceSave:)` itself reads:
    /// `sheet.entries.first` is the wrapper (its `name`/`description` become
    /// the new item's), whose own first entry's `entries` are the actual
    /// outcome rows. `nil` if `sheet` doesn't have that shape.
    @MainActor
    init?(sheet: SheetModel) {
        guard let wrapper = sheet.entries.first else { return nil }
        let rows = wrapper.entries.first?.entries ?? []
        self.init(
            name: wrapper.name,
            description: wrapper.description,
            entries: rows.map { Entry(name: $0.name, content: $0.description) }
        )
    }

    /// Rebuilds the minimal `SheetModel` tree `addItem(sheet:forceSave:)`
    /// expects — the inverse of `init(sheet:)` — so a decoded transfer can be
    /// fed straight back into the same function the local Save path uses.
    @MainActor
    func makeSheetModel() -> SheetModel {
        let rows = entries.map { entry in
            SheetModel(source: .empty, name: entry.name, description: entry.content, entries: [])
        }
        let nested = SheetModel(source: .empty, name: "", description: "", entries: rows)
        let wrapper = SheetModel(source: .empty, name: name, description: description, entries: [nested])
        return SheetModel(source: .empty, name: "", description: "", entries: [wrapper])
    }
}
