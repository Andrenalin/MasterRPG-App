// @copyright André Trettin

import CoreRPG
import Foundation
import CoreGraphics

struct PdfModel: Identifiable, Sendable, Codable {
    init(id: UUID, name: String = "", description: String = "", tags: [String] = [], category: ItemListCategory = .rules, displayState: Int = 0, fileUrl: FileUrl? = nil, entries: [PdfEntryModel] = []) {
        self.id = id
        self.name = name
        self.description = description
        self.tags = tags
        self.category = category
        self.displayState = displayState
        self.fileUrl = fileUrl
        self.entries = entries
    }

    var id: UUID
    var name: String = ""
    var description: String = ""
    var tags: [String] = []
    var category: ItemListCategory = .rules
    var displayState: Int = 0
    var fileUrl: FileUrl? = nil
    var entries: [PdfEntryModel] = []
}

struct PdfEntryModel: Identifiable, Sendable, Codable {
    init(id: UUID, itemId: UUID, index: Int = 0, name: String = "", content: String = "", bounds: CGRect = .zero, pageLabel: String = "") {
        self.id = id
        self.itemId = itemId
        self.index = index
        self.name = name
        self.content = content
        self.bounds = bounds
        self.pageLabel = pageLabel
    }
    
    var id: UUID
    var itemId: UUID
    var index: Int = 0
    var name: String = ""
    var content: String = ""
    var bounds: CGRect = .zero
    var pageLabel: String = ""
}
