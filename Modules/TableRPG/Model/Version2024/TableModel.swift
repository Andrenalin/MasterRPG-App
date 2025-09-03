// @copyright André Trettin

import CoreRPG
import Foundation

struct TableModel: Identifiable, Sendable, Codable {
    init(id: UUID, name: String = "", description: String = "", tags: [String] = [], category: ItemListCategory = .rules, displayState: Int = 0, diceId: UUID? = nil, tableType: String = "", entries: [TableEntryModel] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.category = category
        self.displayState = displayState
        self.diceId = diceId
        self.tableType = tableType
        self.entries = entries
    }

    var id: UUID
    var name: String = ""
    var description: String = ""
    var tags: [String] = []
    var category: ItemListCategory = .rules
    var displayState: Int = 0
    var diceId: UUID? = nil
    var tableType: String = ""
    var entries: [TableEntryModel] = []
}

struct TableEntryModel: Identifiable, Sendable, Codable {
    init(id: UUID, itemId: UUID, entryId: UUID, index: Int = 0, name: String = "", content: String = "") {
        self.id = id
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.content = content
    }
    
    var id: UUID
    var itemId: UUID
    var entryId: UUID
    var index: Int = 0
    var name: String = ""
    var content: String = ""
}
