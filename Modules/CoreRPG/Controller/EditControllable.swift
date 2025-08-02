// @copyright André Trettin

import Foundation
import SwiftData

public enum EditControllerAddType {
    case item
    case folder
    case collection
    
    var title: String {
        String(localized: localizedTitle).localizedString
    }
    
    private var localizedTitle: LocalizedStringResource {
        switch self {
        case .item:
            return "Add Item"
        case .folder:
            return "Add Folder"
        case .collection:
            return "Add Collection"
        }
    }
    
    func icon(collection: String) -> String {
        switch self {
        case .item:
            return "plus"
        case .folder:
            return "folder.badge.plus"
        case .collection:
            return collection
        }
    }
}

public protocol EditControllable {
    associatedtype Model: Identifiable where Model.ID == UUID

    @MainActor func addNew(modelContext: ModelContext, type: EditControllerAddType) -> Model
    func delete(model: Model)
    
    func addItem(itemId: UUID, in modelContext: ModelContext, parentId: UUID?, folderId: UUID?)

    func update(model: Model, name: String, information: String, category: ItemListCategory, tags: [String])
    func resetFile(url: URL?, in model: Model)
}
