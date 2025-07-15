// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

struct ContextMenuController: ItemListContextMenuControllable {
    let editController: EditController
    let model: PhotoDataModel
    
    var itemName: String {
        model.name
    }
    
    func copyItem() {
        editController.copy(model: model)
    }
    
    func deleteItem() {
        editController.delete(model: model)
    }
    
    func exportItem() {
        
    }
    
    func generateLink() {
        
    }
}
