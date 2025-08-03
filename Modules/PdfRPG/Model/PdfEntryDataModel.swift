// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model
public final class PdfEntryDataModel {
    init(id: UUID = UUID(), index: Int16 = 0, parentId: UUID? = nil, childId: UUID? = nil, item: PdfDataModel? = nil) {
        self.id = id
        self.index = index
        self.parentId = parentId
        self.childId = childId
        self.item = item
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    var index: Int16 = 0
    public var parentId: UUID?
    public var childId: UUID?
    var item: PdfDataModel?
}

extension PdfEntryDataModel: EntryDataAccessable {
    public var name: String {
        guard let entry = PdfDataModel.model(modelContext: modelContext, id: childId) else { return "Name unknown" }
        return entry.name
    }
}

extension PdfEntryDataModel {
    var entryModel: PdfEntryModel {
        PdfEntryModel(id: id)
    }
}


@Model
public final class PdfBookmarkDataModel {
    init(id: UUID = UUID(), index: Int16 = 0, name: String = "", content: String = "", bounds: String = "", pageLabel: String = "", parent: PdfDataModel? = nil) {
        self.id = id
        self.index = index
        self.name = name
        self.content = content
        self.bounds = bounds
        self.pageLabel = pageLabel
        self.parent = parent
    }
    
    @Attribute(.preserveValueOnDeletion)
    public var id: UUID = UUID()
    var index: Int16 = 0
    public var name: String = ""
    var content: String = ""
    var bounds: String = ""
    var pageLabel: String = ""
    var parent: PdfDataModel?
}

extension PdfBookmarkDataModel: EntryDataAccessable {}

extension PdfBookmarkDataModel {
    var entryModel: PdfEntryModel {
        PdfEntryModel(id: id)
    }
}
