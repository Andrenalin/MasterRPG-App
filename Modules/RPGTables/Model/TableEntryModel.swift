// @copyright André Trettin

import AndrenalinKit
import Foundation

public struct TableEntryModel: Identifiable, Equatable, Hashable, Codable, @unchecked Sendable {
    init(id: UUID, name: String, content: String, displayState: Int = 0, diceResult: String? = nil) {
        self.id = id
        self.name = name
        self.content = content
        self.displayState = displayState

        self.diceResult = diceResult
    }

    init(id: UUID, name: CRDT<String>, content: CRDT<String>, displayState: Int, diceResult: String?) {
        self.id = id
        _name = name
        _content = content
        self.displayState = displayState

        self.diceResult = diceResult
    }

    public let id: UUID
    @CRDT public var name: String
    @CRDT public var content: String
    public var displayState: Int = 0

    public var diceResult: String? = nil
}

// MARK: - EntryDataAccessable

extension TableEntryModel: EntryDataAccessable {
    public var childId: UUID { id }
    public static func newChild(id: UUID) -> Self {
        empty(id)
    }

    public static var empty: TableEntryModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> TableEntryModel {
        TableEntryModel(id: id, name: "", content: "")
    }

    public func duplicate() -> TableEntryModel {
        TableEntryModel(id: UUID(), name: name, content: content, displayState: displayState, diceResult: nil)
    }

    public func filter(with search: String) -> Bool {
        (search.isEmpty || name.localizedCaseInsensitiveContains(search) || content.localizedCaseInsensitiveContains(search))
    }
    
    public func linkContent() -> String { content }
}

// MARK: - ItemDiffComparable

extension TableEntryModel: ItemDiffComparable {
    public func merge(_ other: TableEntryModel) -> TableEntryModel {
        TableEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            content: $content.merged(other: other.$content),
            displayState: other.displayState,
            diceResult: other.diceResult
        )
    }

    public func isSame(_ other: TableEntryModel) -> Bool {
        name == other.name && content == other.content
    }
}

// MARK: - Links

extension TableEntryModel: ItemLinkEditable {
    public var textLinkContent: String {
        entryLinkText(otherValue: "")
    }
}

extension TableEntryModel: ItemReferencable {}

// MARK: - Attributed Text with links

extension TableEntryModel {
    public func entryLinkText(otherValue: String) -> String {
        let bold = name.starts(with: "**") ? "" : "**"
        return "\(bold)\(name.trimmingCharacters(in: .whitespacesAndNewlines))\(bold): \(content)\(otherValue)"
    }

    public var nameLinkText: String {
        let bold = name.starts(with: "**") ? "" : "**"
        return "\(bold)\(name.trimmingCharacters(in: .whitespacesAndNewlines))\(bold)"
    }

    public func contentLinkText(otherValue: String) -> String {
        return "\(content)\(otherValue)"
    }
}
