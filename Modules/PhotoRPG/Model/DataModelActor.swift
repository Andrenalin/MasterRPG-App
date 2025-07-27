// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@ModelActor
actor DataModelActor {    
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

    func duplicate(url: URL?) {
        let newModel = PhotoDataModel(
            id: UUID(),
            name: "\(model.name) copy",
            information: model.information,
            category: model.category,
            tags: model.tags,
            displayState: 0,
            degrees: model.degrees,
            url: url,
            entries: []
        )

        modelContext.insert(newModel)
    }
    
    func photoModel() -> PhotoModel {
        model.itemModel
    }
    
    func save() {
        try? modelContext.save()
    }
}
