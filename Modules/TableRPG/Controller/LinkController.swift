// @copyright André Trettin

import CoreRPG
import Foundation

struct LinkController: Sendable {
    var module: NetworkModules
    var itemController: ItemController
    
    var itemControllable: any ItemControllable {
        itemController
    }
}

extension LinkController: LinkControllable {

    @MainActor func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        guard let item = itemController.modelSync(for: itemId) else { return "" }
        guard let entryId else { return item.url(linkNumber: linkNumber) }
        guard let model = itemController.model(for: itemId) else { return "" }
        let name = model[entryId].name
        return item.url(linkNumber: linkNumber, entryId: entryId, name: name)
    }
    
    @MainActor func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            }
            if command == LinkType.show.rawValue {
                toggler?(itemId, module)
            } else {
                // command share
                //await shareResult?.networkActions?.shareId(root.gameController.share(id: itemId))
            }
            return text
        } else {
            if let toggler, entryId == nil {
                toggler(itemId, module)
            }
            guard let item = itemController.modelSync(for: itemId), let model = itemController.model(for: itemId) else { return text }
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId) : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: item.module)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let description: String
            if let entryId {
                description = model[entryId].content
            } else {
                description = "\(item.name) / \(item.information) / \(model.entries.count) Entries"
            }
            let result = "\(sendAction)\(showAction) \(description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }
    
    @MainActor func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? {
        guard module == .table else { return nil }
        return SheetController(itemController: itemController).sheet(for: itemId, level: level)
    }
}
