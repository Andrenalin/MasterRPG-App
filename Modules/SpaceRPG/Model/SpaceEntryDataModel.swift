// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class SpaceEntryDataModel {
    init(id: UUID = UUID(), index: Int16 = 0, parentId: UUID? = nil, childId: UUID? = nil, item: SpaceDataModel? = nil) {
        self.id = id
        self.index = index
        self.childId = childId
        self.space = item
    }
    
    public var id: UUID = UUID()
    var index: Int16 = 0
    public var parentId: UUID?
    public var childId: UUID?
    var space: SpaceDataModel?
}

extension SpaceEntryDataModel: EntryDataAccessable {
    public var name: String {
        guard let entrySpace = SpaceDataModel.model(modelContext: modelContext, id: childId) else { return "Name unknown" }
        return entrySpace.name
    }
}

extension SpaceEntryDataModel {
    var entryModel: SpaceEntryModel {
        SpaceEntryModel(id: id, itemId: childId ?? UUID())
    }
}
