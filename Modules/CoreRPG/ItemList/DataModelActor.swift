// @copyright André Trettin

import Foundation
import SwiftData

@ModelActor
public actor DataModelActor {
    private var _id: UUID?
    public var id: UUID {
        _id.unsafelyUnwrapped
    }
    
    private var _model: ItemDataModel?
    public var model: ItemDataModel {
        _model.unsafelyUnwrapped
    }
    
    public func setup(id: UUID) {
        self._id = id
        self._model = ItemDataModel.model(modelContext: modelContext, id: id)
    }

    public var module: NetworkModules {
        model.module
    }

    public var name: String {
        model.name
    }

    public var category: ItemListCategory {
        model.category
    }

    public var fileUrl: FileUrl? {
        model.fileUrl
    }

    public func update(name: String) {
        model.reset(name: name)
    }
    
    public func update(url: URL?) {
        model.url = url
    }

    public func duplicate(newId: UUID, url: URL?) {
        let newModel = ItemDataModel(
            id: newId,
            module: model.module,
            name: "\(model.name) copy",
            information: model.information,
            category: model.category,
            tags: model.tags,
            url: url,
            displayState: 0,
            parentId: model.parentId,
            entries: []
        )

        modelContext.insert(newModel)
    }
    
//    func itemModel() -> AudioModel {
//        model.itemModel
//    }
    
    public func save() {
        try? modelContext.save()
    }
}
