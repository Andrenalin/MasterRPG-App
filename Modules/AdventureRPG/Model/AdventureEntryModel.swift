// @copyright André Trettin

import CoreRPG
import Foundation

public struct AdventureEntryModel: Identifiable, Equatable, Hashable, Codable, @unchecked Sendable {
    public init(id: UUID, name: String, content: String, displayState: Int = 0) {
        self.id = id
        self.name = name
        self.content = content
        self.displayState = displayState
    }

    public init(id: UUID, name: CRDT<String>, content: CRDT<String>, displayState: Int = 0) {
        self.id = id
        _name = name
        _content = content
        self.displayState = displayState
    }

    public var id: UUID
    @CRDT public var name: String
    @CRDT public var content: String
    public var displayState: Int
}

extension AdventureEntryModel: EntryDataAccessable {
    public var childId: UUID { id }
    public static func newChild(id: UUID) -> Self {
        empty(id)
    }

    public static var empty: AdventureEntryModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> AdventureEntryModel {
        AdventureEntryModel(id: id, name: "", content: "")
    }

    public func duplicate() -> AdventureEntryModel {
        AdventureEntryModel(id: UUID(), name: name, content: content, displayState: displayState)
    }
    
    public func filter(with search: String) -> Bool {
        (search.isEmpty || name.localizedCaseInsensitiveContains(search) || content.localizedCaseInsensitiveContains(search))
    }

    public func linkContent() -> String { content }
}

extension AdventureEntryModel: ItemDiffComparable {
    public func merge(_ other: AdventureEntryModel) -> AdventureEntryModel {
        AdventureEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            content: $content.merged(other: other.$content),
            displayState: other.displayState
        )
    }

    public func isSame(_ other: AdventureEntryModel) -> Bool {
        name == other.name &&
        content == other.content
    }
}

extension AdventureEntryModel: ItemLinkEditable {
    public var textLinkContent: String {
        content
    }
    
    public func entryLinkText() -> String {
        let bold = name.starts(with: "**") ? "" : "**"
        return "\(bold)\(name.trimmingCharacters(in: .whitespacesAndNewlines))\(bold): \(content)"
    }
}

extension AdventureEntryModel: ItemReferencable {}
