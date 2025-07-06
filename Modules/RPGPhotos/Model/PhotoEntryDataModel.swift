//
//  RPGPhotoEntry.swift
//  MasterRPG
//
//  Created by Andre Trettin on 02.07.25.
//


// @copyright André Trettin

import Foundation
import SwiftData

@Model 
public final class PhotoEntryDataModel {
    init(id: UUID = UUID(), index: Int16 = 0, parentId: UUID? = nil, photo: PhotoDataModel? = nil) {
        self.id = id
        self.index = index
        self.parentId = parentId
        self.photo = photo
    }
    
    public var id: UUID?
    var index: Int16 = 0
    var parentId: UUID?
    var photo: PhotoDataModel?
}
