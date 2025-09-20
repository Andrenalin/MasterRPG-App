// @copyright André Trettin

import Foundation
import SwiftData

public protocol ModelCachable: Identifiable, PersistentModel {
    var itemId: UUID { get }
    var displayState: Int { get set }
    
    static func newModel(for itemId: UUID) -> Self
}

@MainActor @Observable
public final class ModelCacheModel<Model: ModelCachable> {
    public init(models: [UUID : Model] = [:]) {
        self.models = models
    }
    @ObservationIgnored
    var models: [UUID: Model] = [:]
}

public protocol ModelCacheControllable: ItemControllable {
    associatedtype Model: ModelCachable
    var modelCacheModel: ModelCacheModel<Model> { get }
}

public extension ModelCacheControllable {
    @MainActor func clean() {
        let modelContext = ModelContext(container)
        let predicate = #Predicate<Model> { $0.displayState == 2 }
        let fetchDesc = FetchDescriptor<Model>(predicate: predicate)
        guard let models: [Model] = try? modelContext.fetch(fetchDesc) else { return }
        for model in models {
            modelCacheModel.models.removeValue(forKey: model.itemId)
            modelContext.delete(model)
        }
        cleanDeleted()
    }
    
    @MainActor func model(for itemId: UUID?) -> Model? {
        guard let itemId else { return nil }
        if let model = modelCacheModel.models[itemId] {
            return model
        }
        let predicate = #Predicate<Model> { $0.itemId == itemId }
        let fetchDesc = FetchDescriptor<Model>(predicate: predicate)
        let models: [Model] = (try? container.mainContext.fetch(fetchDesc)) ?? []
        guard let model = models.first else {
            let newModel = Model.newModel(for: itemId)
            container.mainContext.insert(newModel)
            try? container.mainContext.save()
            modelCacheModel.models[itemId] = newModel
            return newModel
        }
        modelCacheModel.models[itemId] = model
        return model
    }
}
