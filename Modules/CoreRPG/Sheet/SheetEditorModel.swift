// @copyright André Trettin

import Foundation
import SwiftUI

@MainActor @Observable public final class SheetEditorModel {
    public init(itemId: UUID = UUID(), entryId: UUID? = nil, module: NetworkModules = .none) {
        self.itemId = itemId
        self.entryId = entryId
        self.module = module
    }
    
    public var itemId: UUID
    public var entryId: UUID?
    public var module: NetworkModules
    
    func setEdit(source: ItemRowModel) {
        self.itemId = source.itemId
        self.entryId = source.entryId
        self.module = source.typeId        
    }
}
