// @copyright André Trettin

import Foundation
import SwiftData

@Model 
public final class EntryDataModel {
    public init(id: UUID = UUID(), index: Int = 0, parentId: UUID, childId: UUID, item: ItemDataModel? = nil) {
        self.id = id
        self.index = index
        self.parentId = parentId
        self.childId = childId
        self.item = item
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    public var index: Int = 0
    public var parentId: UUID = UUID()
    public var childId: UUID = UUID()
    var item: ItemDataModel?
}

extension EntryDataModel {
    public static func empty(id: UUID) -> EntryDataModel {
        EntryDataModel(id: id, parentId: UUID(), childId: UUID())
    }
    public var name: String {
        guard let entry = ItemDataModel.model(modelContext: modelContext, id: childId) else { return "Name unknown" }
        return entry.name
    }        
}

extension EntryDataModel {
//    var entryModel: AudioEntryModel {
//        AudioEntryModel(id: id, itemId: childId ?? UUID())
//    }
}
