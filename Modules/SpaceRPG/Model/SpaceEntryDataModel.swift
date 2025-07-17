// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class SpaceEntryDataModel {
    init(id: UUID = UUID(), index: Int16 = 0, parentId: UUID? = nil, spaceId: UUID? = nil, space: SpaceDataModel? = nil) {
        self.id = id
        self.index = index
        self.spaceId = spaceId
        self.space = space
    }
    
    public var id: UUID = UUID()
    var index: Int16 = 0
    var parentId: UUID?
    var spaceId: UUID?
    var space: SpaceDataModel?
}

extension SpaceEntryDataModel: EntryDataAccessable {
    public var name: String {
        guard let modelContext, let spaceId, let entrySpace = SpaceDataModel.model(modelContext: modelContext, id: spaceId) else { return "Name unknown" }
        return entrySpace.name
    }
}

extension SpaceEntryDataModel {
    var spaceEntryModel: SpaceEntryModel {
        SpaceEntryModel(id: id, spaceId: spaceId ?? UUID())
    }
}
