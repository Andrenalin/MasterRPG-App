// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class PdfEntryDataModel {
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

extension PdfEntryDataModel: EntryDataAccessable {}

extension PdfEntryDataModel {
    var entryModel: PdfEntryModel {
        PdfEntryModel(id: id)
    }
}
