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
    
    init(id: UUID = UUID(), name: String, category: ItemListCategory = .photo, description: String = "Long Descripotion test", tags: [String] = ["Test"], displayState: Int = 0, isGroupHiddenToggle: Bool = false, fileUrl: FileUrl? = nil, entries: [FakeEntryModel] = []) {
        self.id = id
        self.name = name
        self.category = category
        self.description = description
        self.tags = tags
        self.displayState = displayState
        self.isGroupHiddenToggle = isGroupHiddenToggle
        self.fileUrl = fileUrl
        self.entries = entries
    }
    
    var id: UUID
    var name: String
    var category: ItemListCategory
    var description: String
    var tags: [String]
    var displayState: Int
    var isGroupHiddenToggle: Bool
    var fileUrl: FileUrl?
    var parentId: UUID?
    
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
    
    func filter(filter: String, includeEntries: Bool) -> Bool { true }
    
    func isEqual(other: FakeItemModel) -> Bool { false }
    
    @MainActor func replace(with model: FakeItemModel) -> Bool { false }
    
    func isSame(_ other: FakeItemModel) -> Bool { false }
    
    func merge(_ other: FakeItemModel) -> Self { self }
    
    static func == (lhs: FakeItemModel, rhs: FakeItemModel) -> Bool { false }
    
    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
    private enum CodingKeys: CodingKey {
        case _entries
        case _id
        case _name
        case _category
        case _description
        case _tags
        case _displayState
        case _isGroupHiddenToggle
    }
    
    init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<FakeItemModel.CodingKeys> = try decoder.container(keyedBy: FakeItemModel.CodingKeys.self)
        
        self._entries = try container.decode([FakeEntryModel].self, forKey: FakeItemModel.CodingKeys._entries)
        self._id = try container.decode(UUID.self, forKey: FakeItemModel.CodingKeys._id)
        self._name = try container.decode(String.self, forKey: FakeItemModel.CodingKeys._name)
        self._category = try container.decode(ItemListCategory.self, forKey: FakeItemModel.CodingKeys._category)
        self._description = try container.decode(String.self, forKey: FakeItemModel.CodingKeys._description)
        self._tags = try container.decode([String].self, forKey: FakeItemModel.CodingKeys._tags)
        self._displayState = try container.decode(Int.self, forKey: FakeItemModel.CodingKeys._displayState)
        self._isGroupHiddenToggle = try container.decode(Bool.self, forKey: FakeItemModel.CodingKeys._isGroupHiddenToggle)
        
    }
    
    final func encode(to encoder: any Encoder) throws {
        var container: KeyedEncodingContainer<FakeItemModel.CodingKeys> = encoder.container(keyedBy: FakeItemModel.CodingKeys.self)
        
        try container.encode(self._entries, forKey: FakeItemModel.CodingKeys._entries)
        try container.encode(self._id, forKey: FakeItemModel.CodingKeys._id)
        try container.encode(self._name, forKey: FakeItemModel.CodingKeys._name)
        try container.encode(self._category, forKey: FakeItemModel.CodingKeys._category)
        try container.encode(self._description, forKey: FakeItemModel.CodingKeys._description)
        try container.encode(self._tags, forKey: FakeItemModel.CodingKeys._tags)
        try container.encode(self._displayState, forKey: FakeItemModel.CodingKeys._displayState)
        try container.encode(self._isGroupHiddenToggle, forKey: FakeItemModel.CodingKeys._isGroupHiddenToggle)
    }
}
