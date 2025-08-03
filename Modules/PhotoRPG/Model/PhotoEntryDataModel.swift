// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class PhotoEntryDataModel {
    init(id: UUID = UUID(), index: Int = 0, parentId: UUID? = nil, childId: UUID? = nil, item: PhotoDataModel? = nil) {
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
    var item: PhotoDataModel?
}

extension PhotoEntryDataModel: EntryDataAccessable {
    public var name: String {
        guard let entry = PhotoDataModel.model(modelContext: modelContext, id: childId) else { return "Name unknown" }
        return entry.name
    }        
}

extension PhotoEntryDataModel {
    var entryModel: PhotoEntryModel {
        PhotoEntryModel(id: id, itemId: childId ?? UUID())
    }
}
