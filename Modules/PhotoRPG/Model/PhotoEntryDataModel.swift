// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class PhotoEntryDataModel {
    init(id: UUID = UUID(), index: Int16 = 0, parentId: UUID? = nil, itemId: UUID? = nil, item: PhotoDataModel? = nil) {
        self.id = id
        self.index = index
        self.parentId = parentId
        self.itemId = itemId
        self.item = item
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    var index: Int16 = 0
    var parentId: UUID?
    var itemId: UUID?
    var item: PhotoDataModel?
}

extension PhotoEntryDataModel: EntryDataAccessable {
    public var name: String {
        guard let modelContext, let itemId, let entryPhoto = PhotoDataModel.model(modelContext: modelContext, id: itemId) else { return "Name unknown" }
        return entryPhoto.name
    }        
}

extension PhotoEntryDataModel {
    var entryModel: PhotoEntryModel {
        PhotoEntryModel(id: id, photoId: itemId ?? UUID())
    }
}
