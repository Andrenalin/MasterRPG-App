// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
public final class CharacterEntryDataModel {
    public init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", value: String = "", valueId: UUID? = nil) {
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.value = value
        self.valueId = valueId
    }
    
    var itemId: UUID = UUID()
    var entryId: UUID = UUID()
    var index: Int = 0
    
    var name: String = ""
    var value: String = ""
    var valueId: UUID? = nil
}

// MARK: - Conversion methods for Version2024 compatibility
extension CharacterEntryDataModel {
    convenience init(_ model: CharacterEntryModel) {
        self.init(
            itemId: model.itemId,
            entryId: model.entryId,
            index: model.index,
            name: model.name,
            value: model.value,
            valueId: model.valueId
        )
    }
    
    var characterEntryModel: CharacterEntryModel {
        CharacterEntryModel(
            id: entryId,
            itemId: itemId,
            entryId: entryId,
            index: index,
            name: name,
            value: value,
            valueId: valueId
        )
    }
    
    func replace(_ model: CharacterEntryModel) {
        itemId = model.itemId
        entryId = model.entryId
        index = model.index
        name = model.name
        value = model.value
        valueId = model.valueId
    }
}
