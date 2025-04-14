// @copyright André Trettin

import AndrenalinKit
import Foundation

struct AdventureEntryModel: Identifiable, Equatable, Hashable, Codable, @unchecked Sendable {
    init(id: UUID, name: String, content: String, displayState: Int = 0) {
        self.id = id
        self.name = name
        self.content = content
        self.displayState = displayState
    }

    init(id: UUID, name: CRDT<String>, content: CRDT<String>, displayState: Int = 0) {
        self.id = id
        _name = name
        _content = content
        self.displayState = displayState
    }

    var id: UUID
    @CRDT var name: String
    @CRDT var content: String
    var displayState: Int
}

extension AdventureEntryModel: EntryDataAccessable {
    static var empty: AdventureEntryModel { empty(UUID()) }
    static func empty(_ id: UUID) -> AdventureEntryModel {
        AdventureEntryModel(id: id, name: "", content: "")
    }

    func duplicate() -> AdventureEntryModel {
        AdventureEntryModel(id: UUID(), name: name, content: content, displayState: displayState)
    }
    
    func filter(with search: String) -> Bool {
        (search.isEmpty || name.localizedCaseInsensitiveContains(search) || content.localizedCaseInsensitiveContains(search))
    }

    func linkContent() -> String { content }
}

extension AdventureEntryModel: ItemDiffComparable {
    func merge(_ other: AdventureEntryModel) -> AdventureEntryModel {
        AdventureEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            content: $content.merged(other: other.$content),
            displayState: other.displayState
        )
    }

    func isSame(_ other: AdventureEntryModel) -> Bool {
        name == other.name &&
        content == other.content
    }
}

extension AdventureEntryModel: ItemLinkEditable {
    var textLinkContent: String {
        content
    }
    
    func entryLinkText() -> String {
        let bold = name.starts(with: "**") ? "" : "**"
        return "\(bold)\(name.trimmingCharacters(in: .whitespacesAndNewlines))\(bold): \(content)"
    }
}

extension AdventureEntryModel: ItemReferencable {}
