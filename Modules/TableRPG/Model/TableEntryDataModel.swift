// @copyright André Trettin

import Foundation
import SwiftData

@Model 
public final class TableEntryDataModel {
    public init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "", parent: TableDataModel? = nil) {
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.content = content
    }
    
    var itemId: UUID = UUID()
    var entryId: UUID = UUID()
    var index: Int = 0
    
    var name: String = ""
    var content: String = ""
    
    //@CodableIgnored
    var parent: TableDataModel? = nil
    
    // MARK: Codable
    
    struct TableEntryDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "") {
            self.itemId = itemId
            self.entryId = entryId
            self.index = index
            self.name = name
            self.content = content
        }
        var itemId: UUID = UUID()
        var entryId: UUID = UUID()
        var index: Int = 0
        var name: String = ""
        var content: String = ""
    }
    
    convenience init(_ model: TableEntryDataModelCodable) {
        self.init(itemId: model.itemId, entryId: model.entryId, index: model.index, name: model.name, content: model.content)
    }
    
    var codableModel: TableEntryDataModelCodable {
        TableEntryDataModelCodable(
            itemId: itemId,
            entryId: entryId,
            index: index,
            name: name,
            content: content
        )
    }
    
    func replace(_ model: TableEntryDataModelCodable) {
        itemId = model.itemId
        entryId = model.entryId
        index = model.index
        name = model.name
        content = model.content
    }
}
