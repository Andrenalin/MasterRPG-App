// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@ModelActor
actor PhotoDataModelActor {
    
    private var _id: UUID?
    var id: UUID {
        _id.unsafelyUnwrapped
    }
    
    private var _model: PhotoDataModel?
    var model: PhotoDataModel {
        _model.unsafelyUnwrapped
    }
    
    func setup(id: UUID) {
        self._id = id
        self._model = PhotoDataModel.model(modelContext: modelContext, id: id)
    }
    
    var name: String {
        model.name
    }

    var category: ItemListCategory {
        model.category
    }

    var fileUrl: FileUrl? {
        model.fileUrl
    }

    func update(name: String) {
        model.reset(name: name)
    }
    
    func update(url: URL?) {
        model.url = url
    }

    func save() {
        try? modelContext.save()
    }
}
