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
//        guard let models = itemController.models(for: item.id) else { return }
        let newItemId = UUID()
//        let duplicat = model.duplicate(newItemId: newItemId)
//        let modelContext = itemController.container.mainContext
//        modelContext.insert(duplicat)
//        try? modelContext.save()
//        duplicat.entries.forEach { entry in
//            let updatedContent = linkRegisterController.replaceLinks(in: entry.content, newItemId: newItemId, newEntryId: entry.entryId)
//            entry.content <=> updatedContent
//        }
        duplicateDataModel(item: item, newItemId: newItemId)
    }
}

// MARK: - Bookmarks

extension EditController {
    func addBookmark(model: ItemDataModel, bookmark: PdfDataModel) {
        bookmark.itemId = model.id
        try? model.modelContext?.save()
    }
    
    func createBookmark(itemId: UUID, content: String, page: String, bounds: CGRect) -> PdfDataModel {
        let name = String(content.split(separator: " ").first ?? "Unnamed")
        return PdfDataModel(id: UUID(), itemId: itemId, name: name, content: content, bounds: bounds, pageLabel: page)
    }
}
