// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class DiceEntryDataModel {
    init(id: UUID = UUID(), index: Int = 0, parentId: UUID? = nil, childId: UUID? = nil, item: DiceDataModel? = nil) {
        self.id = id
        self.index = index
        self.parentId = parentId
        self.childId = childId
        self.item = item
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    public var index: Int = 0
    public var parentId: UUID?
    public var childId: UUID?
    var item: DiceDataModel?
}

extension DiceEntryDataModel: EntryDataAccessable {
    public var name: String {
        guard let entry = DiceDataModel.model(modelContext: modelContext, id: childId) else { return "Name unknown" }
        return entry.name
    }        
}

extension DiceEntryDataModel {
    var entryModel: DiceEntryModel {
        DiceEntryModel(id: id, itemId: childId ?? UUID())
    }
}
