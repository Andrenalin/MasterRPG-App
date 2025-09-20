// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController {
    @MainActor
    init(itemController: ItemController, fileUrlDataController: FileUrlDataController) {
        self.itemController = itemController
        self.fileUrlDataController = fileUrlDataController
    }

    let itemController: ItemController
    let fileUrlDataController: FileUrlDataController?
}

extension EditController: EditControllable {
    var itemControllable: any ItemControllable {
        itemController
    }

    @MainActor func duplicate(item: ItemDataModel) {
       guard let model = itemController.model(for: item.id) else { return }
        let newItemId = UUID()
        let duplicat = model.duplicate(newItemId: newItemId)
        let modelContext = itemController.container.mainContext
        modelContext.insert(duplicat)
        try? modelContext.save()
        duplicateDataModel(item: item, newItemId: newItemId)
    }
}

// MARK: - Bookmarks

extension EditController {
    func addBookmark(model: ItemDataModel, bookmark: PdfEntryDataModel) {
        bookmark.itemId = model.id
        try? model.modelContext?.save()
    }
    
    func createBookmark(itemId: UUID, content: String, page: String, bounds: CGRect) -> PdfEntryDataModel {
        let name = String(content.split(separator: " ").first ?? "Unnamed")
        return PdfEntryDataModel(itemId: itemId, entryId: UUID(), name: name, content: content, bounds: bounds, pageLabel: page)
    }
}
