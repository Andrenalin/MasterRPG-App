// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData
#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

struct ContextMenuController: ItemListContextMenuControllable {
    let editController: EditController
    let model: SpaceDataModel
    
    var itemName: String {
        model.name
    }
    
    func copyItem() {
        editController.copy(model: model)
    }
    
    func deleteItem() {
        editController.delete(model: model)
    }
    
    func exportItem() -> any NavigationDestination {
        InternalRoute.export(id: model.id)
    }
    
    func generateLink() {
        let linkText = model.url(linkNumber: 0)
        
#if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(linkText, forType: .string)
#elseif !os(tvOS)
        let pasteboard = UIPasteboard.general
        pasteboard.string = linkText
#endif

    }
}
