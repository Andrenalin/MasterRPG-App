// @copyright André Trettin

import AndrenalinKit
import Foundation

struct PdfEntryModel: Identifiable, Equatable, Hashable, Codable {
    init(id: UUID, name: String, content: String, pageNumber: String, bounds: CGRect, displayState: Int = 0) {
        self.id = id
        self.name = name
        self.content = content
        self.pageLabel = pageNumber
        self.bounds = bounds
        self.displayState = displayState
    }

    init(id: UUID, name: CRDT<String>, content: CRDT<String>, pageNumber: String, bounds: CGRect = .zero, displayState: Int) {
        self.id = id
        _name = name
        _content = content
        self.pageLabel = pageNumber
        self.bounds = bounds
        self.displayState = displayState
    }

    let id: UUID
    @CRDT var name: String
    @CRDT var content: String
    var pageLabel: String
    var bounds: CGRect
    var displayState: Int = 0
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(content)
        hasher.combine(pageLabel)
    }
}

extension PdfEntryModel: EntryDataAccessable {    
    static var empty: PdfEntryModel { empty(UUID()) }

    static func empty(_ id: UUID) -> PdfEntryModel {
        PdfEntryModel(id: id, name: "", content: "", pageNumber: "", bounds: .zero)
    }

    func duplicate() -> PdfEntryModel {
        PdfEntryModel(id: UUID(), name: self.name, content: content, pageNumber: pageLabel, bounds: bounds, displayState: displayState)
    }

    func filter(_ filter: String, selectedTags _: [TagFilterSelection]) -> Bool {
        filter.isEmpty || name.localizedCaseInsensitiveContains(filter) ||
        content.localizedCaseInsensitiveContains(filter)
    }
    
    func filter(with search: String) -> Bool {
        true
    }
    
    func linkContent() -> String { content }
}

extension PdfEntryModel: ItemDiffComparable {
    func merge(_ other: PdfEntryModel) -> PdfEntryModel {
        PdfEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            content: $content.merged(other: other.$content),
            pageNumber: other.pageLabel,
            bounds: other.bounds,
            displayState: other.displayState
        )
    }

    func isSame(_ other: PdfEntryModel) -> Bool {
        name == other.name &&
        content == other.content &&
        pageLabel == other.pageLabel &&
        bounds == other.bounds
    }
}

extension PdfEntryModel {
    static func createEntry(content: String, page: String, bounds: CGRect) -> PdfEntryModel {
        let name = String(content.split(separator: " ").first ?? "Unnamed")
        let entry = PdfEntryModel(id: UUID(), name: name, content: content, pageNumber: page, bounds: bounds)
        return entry
    }
}
