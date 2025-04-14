// @copyright André Trettin

import AndrenalinKit
import Foundation

struct TableEntryModel: Identifiable, Equatable, Hashable, Codable, @unchecked Sendable {
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

    let id: UUID
    @CRDT var name: String
    @CRDT var content: String
    var displayState: Int = 0

    var diceResult: String? = nil
}

// MARK: - EntryDataAccessable

extension TableEntryModel: EntryDataAccessable {
    static var empty: TableEntryModel { empty(UUID()) }
    static func empty(_ id: UUID) -> TableEntryModel {
        TableEntryModel(id: id, name: "", content: "")
    }

    func duplicate() -> TableEntryModel {
        TableEntryModel(id: UUID(), name: name, content: content, displayState: displayState, diceResult: nil)
    }

    func filter(with search: String) -> Bool {
        (search.isEmpty || name.localizedCaseInsensitiveContains(search) || content.localizedCaseInsensitiveContains(search))
    }
    
    func linkContent() -> String { content }
}

// MARK: - ItemDiffComparable

extension TableEntryModel: ItemDiffComparable {
    func merge(_ other: TableEntryModel) -> TableEntryModel {
        TableEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            content: $content.merged(other: other.$content),
            displayState: other.displayState,
            diceResult: other.diceResult
        )
    }

    func isSame(_ other: TableEntryModel) -> Bool {
        name == other.name && content == other.content
    }
}

// MARK: - Links

extension TableEntryModel: ItemLinkEditable {
    var textLinkContent: String {
        entryLinkText(otherValue: "")
    }
}

extension TableEntryModel: ItemReferencable {}

// MARK: - Attributed Text with links

extension TableEntryModel {
    func entryLinkText(otherValue: String) -> String {
        let bold = name.starts(with: "**") ? "" : "**"
        return "\(bold)\(name.trimmingCharacters(in: .whitespacesAndNewlines))\(bold): \(content)\(otherValue)"
    }

    var nameLinkText: String {
        let bold = name.starts(with: "**") ? "" : "**"
        return "\(bold)\(name.trimmingCharacters(in: .whitespacesAndNewlines))\(bold)"
    }

    func contentLinkText(otherValue: String) -> String {
        return "\(content)\(otherValue)"
    }
}
