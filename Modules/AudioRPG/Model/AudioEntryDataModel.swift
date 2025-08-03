// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class AudioEntryDataModel {
    init(id: UUID = UUID(), index: Int = 0, parentId: UUID? = nil, childId: UUID? = nil, item: AudioDataModel? = nil) {
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
    var item: AudioDataModel?
}

extension AudioEntryDataModel: EntryDataAccessable {
    public var name: String {
        guard let entryPhoto = AudioDataModel.model(modelContext: modelContext, id: childId) else { return "Name unknown" }
        return entryPhoto.name
    }        
}

extension AudioEntryDataModel {
    var entryModel: AudioEntryModel {
        AudioEntryModel(id: id, itemId: childId ?? UUID())
    }
}
