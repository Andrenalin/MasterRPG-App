// @copyright André Trettin

import Foundation
import SwiftData

public protocol EditControllable {
    associatedtype Model: Identifiable where Model.ID == UUID

    func addNew(modelContext: ModelContext, listMode: ListModel.ListMode) -> Model
    func delete(model: Model)
    
    func update(model: Model, name: String, information: String, category: ItemListCategory, tags: [String])
    func resetFile(url: URL?, in model: Model)
}
