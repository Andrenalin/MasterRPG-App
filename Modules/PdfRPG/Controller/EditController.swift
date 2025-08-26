// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct EditController: EditControllable {
    let itemControllable: any ItemControllable
    let fileUrlDataController: FileUrlDataController?
}

// MARK: - Bookmarks

extension EditController {
    func addBookmark(model: ItemDataModel, bookmark: PdfBookmarkDataModel) {
        bookmark.itemId = model.id
        try? model.modelContext?.save()
    }
    
    func createBookmark(itemId: UUID, content: String, page: String, bounds: CGRect) -> PdfBookmarkDataModel {
        let name = String(content.split(separator: " ").first ?? "Unnamed")
        return PdfBookmarkDataModel(id: UUID(), itemId: itemId, name: name, content: content, bounds: bounds, pageLabel: page)
    }
}
