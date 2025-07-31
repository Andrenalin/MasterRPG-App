// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class SpaceEntryDataModel {
    init(id: UUID = UUID(), index: Int16 = 0, parentId: UUID? = nil, itemId: UUID? = nil, space: SpaceDataModel? = nil) {
        self.id = id
        self.index = index
        self.itemId = itemId
        self.space = space
    }
    
    public var id: UUID = UUID()
    var index: Int16 = 0
    var parentId: UUID?
    var itemId: UUID?
    var space: SpaceDataModel?
}

extension SpaceEntryDataModel: EntryDataAccessable {
    public var name: String {
        guard let modelContext, let itemId, let entrySpace = SpaceDataModel.model(modelContext: modelContext, id: itemId) else { return "Name unknown" }
        return entrySpace.name
    }
}

extension SpaceEntryDataModel {
    var entryModel: SpaceEntryModel {
        SpaceEntryModel(id: id, spaceId: itemId ?? UUID())
    }
}
