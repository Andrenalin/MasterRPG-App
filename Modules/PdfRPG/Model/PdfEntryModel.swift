// @copyright André Trettin

import CoreRPG
import Foundation
import CoreGraphics

public struct PdfEntryModel: Identifiable, Equatable, Hashable, Codable, Sendable {
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

    public let id: UUID
    @CRDT public var name: String
    @CRDT public var content: String
    public var pageLabel: String
    public var bounds: CGRect
    public var displayState: Int = 0
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
        hasher.combine(name)
        hasher.combine(content)
        hasher.combine(pageLabel)
    }
}

extension PdfEntryModel: EntryDataAccessible {
    public var childId: UUID { id }
    public static func newChild(id: UUID) -> Self {
        empty(id)
    }

    public static var empty: PdfEntryModel { empty(UUID()) }

    static func empty(_ id: UUID) -> PdfEntryModel {
        PdfEntryModel(id: id, name: "", content: "", pageNumber: "", bounds: .zero)
    }

    public func duplicate() -> PdfEntryModel {
        PdfEntryModel(id: UUID(), name: self.name, content: content, pageNumber: pageLabel, bounds: bounds, displayState: displayState)
    }

    public func filter(_ filter: String, selectedTags _: [TagFilterSelection]) -> Bool {
        filter.isEmpty || name.localizedStandardContains(filter) ||
        content.localizedStandardContains(filter)
    }

    public func filter(with search: String) -> Bool {
        search.isEmpty || name.localizedStandardContains(search) || content.localizedStandardContains(search)
    }
    
    public func linkContent() -> String { content }
}

extension PdfEntryModel: ItemDiffComparable {
    public func merge(_ other: PdfEntryModel) -> PdfEntryModel {
        PdfEntryModel(
            id: id,
            name: $name.merged(other: other.$name),
            content: $content.merged(other: other.$content),
            pageNumber: other.pageLabel,
            bounds: other.bounds,
            displayState: other.displayState
        )
    }

    public func isSame(_ other: PdfEntryModel) -> Bool {
        name == other.name &&
        content == other.content &&
        pageLabel == other.pageLabel &&
        bounds == other.bounds
    }
}

extension PdfEntryModel {
    public static func createEntry(content: String, page: String, bounds: CGRect) -> PdfEntryModel {
        let name = String(content.split(separator: " ").first ?? "Unnamed")
        let entry = PdfEntryModel(id: UUID(), name: name, content: content, pageNumber: page, bounds: bounds)
        return entry
    }
}
