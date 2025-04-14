// @copyright André Trettin

import SwiftUI

@Observable
final class FakeItemModel: ItemDataAccessable & ItemDiffComparable & ItemDuplicatable & ItemLinkRegistable & Identifiable & Equatable & Hashable & Codable, @unchecked Sendable {
    
    var entries: [FakeEntryModel]
    
    subscript(id: UUID) -> FakeEntryModel {
        get {
            entries.first ?? .empty
        }
        set {
            entries = [newValue]
        }
    }
    
    typealias Entry = FakeEntryModel
    
    init(id: UUID, name: String, category: ItemListCategory, description: String, tags: [String], displayState: Int, isGroupHiddenToggle: Bool, entries: [FakeEntryModel] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.tags = tags
        self.displayState = displayState
        self.isGroupHiddenToggle = isGroupHiddenToggle
        self.entries = entries
    }
    
    var id: UUID
    var name: String
    var category: ItemListCategory
    var description: String
    var tags: [String]
    var displayState: Int
    var isGroupHiddenToggle: Bool

    static let empty: FakeItemModel =  empty(UUID())
    static func empty(_ id: UUID) -> FakeItemModel {
        FakeItemModel(id: id, name: "", category: ItemListCategory.all, description: "", tags: [], displayState: 0, isGroupHiddenToggle: false)
    }
        
    func copy() -> Self {
        .init(id: id, name: name, category: category, description: description, tags: tags, displayState: displayState, isGroupHiddenToggle: isGroupHiddenToggle)
    }
    
    func duplicate() -> Self {
        .init(id: id, name: name, category: category, description: description, tags: tags, displayState: displayState, isGroupHiddenToggle: isGroupHiddenToggle)
    }
    
    func filter(_ filter: String) -> Bool { true }
    
    func isEqual(other: FakeItemModel) -> Bool { false }
    
    func replace(with model: FakeItemModel) -> Bool { false }
    
    func isSame(_ other: FakeItemModel) -> Bool { false }
    
    func merge(_ other: FakeItemModel) -> Self { self }
    
    static func == (lhs: FakeItemModel, rhs: FakeItemModel) -> Bool { false }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
