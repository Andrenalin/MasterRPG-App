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
    
    private var _model: PdfDataModel?
    var model: PdfDataModel {
        _model.unsafelyUnwrapped
    }
    
    func setup(id: UUID) {
        self._id = id
        self._model = PdfDataModel.model(modelContext: modelContext, id: id)
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

    func duplicate(newId: UUID, url: URL?) {
        let newModel = PdfDataModel(
            id: newId,
            name: "\(model.name) copy",
            information: model.information,
            category: model.category,
            tags: model.tags,
            displayState: 0,
            parentId: model.parentId,
            url: url,
            entries: []
        )

        modelContext.insert(newModel)
    }
    
    func itemModel() -> PdfModel {
        model.itemModel
    }
    
    func save() {
        try? modelContext.save()
    }
}
