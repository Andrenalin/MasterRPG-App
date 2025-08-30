// @copyright André Trettin

import Foundation
import SwiftData

@Model
public final class TableEntryDataModel {
    public init(parentId: UUID = UUID(), id: UUID = UUID(), index: Int = 0, name: String = "", content: String = "") {
        self.parentId = parentId
        self.id = id
        self.index = index
        self.name = name
        self.content = content
    }
    
    var parentId: UUID = UUID()
    public var id: UUID = UUID()
    var index: Int = 0
    
    var name: String = ""
    var content: String = ""
}
