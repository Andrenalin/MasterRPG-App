// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
public final class TableEntryDataModel {
    public init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "") {
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.content = content
    }
    
    var itemId: UUID = UUID()
    var entryId: UUID = UUID()
    var index: Int = 0
    
    var name: String = ""
    var content: String = ""
}

// MARK: - Conversion methods for Version2024 compatibility
extension TableEntryDataModel {
    convenience init(_ model: TableEntryModel) {
        self.init(
            itemId: model.itemId,
            entryId: model.entryId,
            index: model.index,
            name: model.name,
            content: model.content
        )
    }
    
    var tableEntryModel: TableEntryModel {
        TableEntryModel(
            id: entryId,
            itemId: itemId,
            entryId: entryId,
            index: index,
            name: name,
            content: content
        )
    }
    
    func replace(_ model: TableEntryModel) {
        itemId = model.itemId
        entryId = model.entryId
        index = model.index
        name = model.name
        content = model.content
    }
}
