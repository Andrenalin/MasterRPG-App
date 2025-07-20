// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import Foundation
import SwiftData
#if os(macOS)
internal import AppKit
#else
internal import UIKit
#endif

struct ContextMenuMultiController: ItemListContextMenuControllable {
    let editController: EditController
    let itemController: ItemController
    let selection: [UUID]
    
    var itemName: String {
        guard let itemId = selection.first, let model = itemController.modelSync(for: itemId) else { return "" }
        if selection.count > 1 {
            return "\(model.name) and \(selection.count - 1) more"
        } else {
            return model.name
        }
    }
    
    func duplicateItem() {
        for itemId in selection {
            guard let model = itemController.modelSync(for: itemId) else { continue }
            editController.duplicate(model: model)
        }
    }
    
    func deleteItem() {
        for itemId in selection {
            guard let model = itemController.modelSync(for: itemId) else { continue }
            editController.delete(model: model)
        }
    }
    
    func exportItem() -> any NavigationDestination {
        InternalRoute.export(ids: selection)
    }
    
    func generateLink() {
        let linkText = selection.compactMap {
            guard let model = itemController.modelSync(for: $0) else { return nil }
            return model.url(linkNumber: 0)
        }.joined(separator: ", ")
        
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
