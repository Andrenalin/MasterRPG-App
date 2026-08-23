// @copyright André Trettin

import Foundation

/// The mutable, link-free portion of a Character value entry that a player may
/// publish during a game. The receiver updates an existing runtime entry only;
/// this payload cannot create entries or replace dice/value links.
public struct GameValueEntryUpdate: Codable, Equatable, Sendable, MessageMapper {
    public init(
        characterId: UUID,
        entryId: UUID,
        name: String,
        typeRawValue: Int,
        isGenerator: Bool,
        value: String,
        displayState: Int,
        path: [Int]? = nil
    ) {
        self.characterId = characterId
        self.entryId = entryId
        self.name = name
        self.typeRawValue = typeRawValue
        self.isGenerator = isGenerator
        self.value = value
        self.displayState = displayState
        self.path = path
    }

    public let characterId: UUID
    public let entryId: UUID
    public let name: String
    public let typeRawValue: Int
    public let isGenerator: Bool
    public let value: String
    public let displayState: Int
    /// Root-to-leaf entry indices (`GameEntryPath.indices`) when `entryId`
    /// lives inside a nested value "group" table rather than directly on
    /// `characterId`. Nil for a top-level entry, and for any payload decoded
    /// from a sender that predates this field — Optional decodes missing keys
    /// as nil, so this is wire-compatible both directions.
    /// See CODE_AUDIT_Game §5.3.
    public let path: [Int]?
}
