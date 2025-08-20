// @copyright André Trettin

import Foundation
import SwiftData

public protocol OldItemControllable: Sendable where ExchangeModel == Model.ExchangeModel {
    associatedtype Model: ItemDataAccessable, ItemDataModelable, ListItemFolderable, PersistentModel
    associatedtype ExchangeModel: ItemDataAccessable, Codable
    
    var container: ModelContainer { get }
    
    func item(for: UUID) async -> ExchangeModel?
    func fileUrl(for: UUID) async -> FileUrl?
}

public extension OldItemControllable {
    func allItemIds() -> [UUID] {
        let modelContext = ModelContext(container)
        let fetchDesc = FetchDescriptor<Model>()
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.map { $0.id }
    }
    
    func itemSync(for id: UUID) -> ExchangeModel? {
        Model.model(modelContext: ModelContext(container), id: id)?.itemModel
    }
    
    func modelSync(for id: UUID) -> Model? {
        Model.model(modelContext: ModelContext(container), id: id)
    }
    
    @MainActor func collections(isFolder: Bool, in parentId: UUID?) -> [Model] {
        let modelContext = ModelContext(container)
        let predicate = #Predicate<Model> { $0.parentId == parentId && $0.displayState == 0 }
        let fetchDesc = FetchDescriptor<Model>(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.filter { $0.category == (isFolder ? .folder : Model.collectionCategory) }
    }
    
    @MainActor func cleanDeleted() {
        let modelContext = ModelContext(container)
        let predicate = #Predicate<Model> { $0.displayState == 2 }
        let fetchDesc = FetchDescriptor<Model>(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        guard let models = try? modelContext.fetch(fetchDesc) else { return }
        for model in models {
            modelContext.delete(model)
        }
    }

}
