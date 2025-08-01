// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ItemController: ItemControllable, Sendable {
    let container: ModelContainer
    
    func item(for id: UUID) async -> PdfModel? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.itemModel()
    }
    
    func itemSync(for id: UUID) -> PdfModel? {
        PdfDataModel.model(modelContext: ModelContext(container), id: id)?.itemModel
    }

    func modelSync(for id: UUID) -> PdfDataModel? {
        PdfDataModel.model(modelContext: ModelContext(container), id: id)
    }

    func allItemIds() -> [UUID] {
        let modelContext = ModelContext(container)
        let fetchDesc = FetchDescriptor<PdfDataModel>()
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.map { $0.id }
    }
    
    func fileUrl(for id: UUID) async -> FileUrl? {
        let actor = DataModelActor(modelContainer: container)
        await actor.setup(id: id)
        return await actor.fileUrl
    }
    
    func collections(isFolder: Bool, in parentId: UUID?) -> [PdfDataModel] {
        let modelContext = ModelContext(container)
        let predicate = #Predicate<PdfDataModel> { $0.parentId == parentId }
        let fetchDesc = FetchDescriptor<PdfDataModel>(predicate: predicate, sortBy: [SortDescriptor(\.name)])
        guard let models = try? modelContext.fetch(fetchDesc) else { return [] }
        return models.filter { $0.category == (isFolder ? .folder : .collection) }
    }
}
