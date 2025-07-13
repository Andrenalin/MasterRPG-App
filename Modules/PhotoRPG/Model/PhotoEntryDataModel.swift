// @copyright André Trettin

import Foundation
import SwiftData

@Model 
public final class PhotoEntryDataModel {
    init(id: UUID = UUID(), index: Int16 = 0, parentId: UUID? = nil, photoId: UUID? = nil, photo: PhotoDataModel? = nil) {
        self.id = id
        self.index = index
        self.parentId = parentId
        self.photoId = photoId
        self.photo = photo
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID?
    var index: Int16 = 0
    var parentId: UUID?
    var photoId: UUID?
    var photo: PhotoDataModel?
}
