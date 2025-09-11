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
    
    @MainActor public func toggleTextLink(model: LinkDataModel, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        let itemId = model.sourceId
        let entryId = model.sourceEntryId
        let module = model.sourceModule
        
        if let command {
            if command == LinkType.remove.rawValue {
                let url = model.url
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
            guard let item = itemController.modelSync(for: itemId), let moduleModel = itemController.model(for: itemId) else { return text }
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? specialLink(linkType: .share, model: model) : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, model: model))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: item.module)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, model: model))" : ""
            let description: String
            if let entryId {
                description = moduleModel[entryId].content
            } else {
                description = "\(item.name) / \(item.information) / \(moduleModel.entries.count) Entries"
            }
            let result = "\(sendAction)\(showAction) \(description)\(removeAction)"
            let url = model.url
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor func validate(itemId: UUID, entryId: UUID?) -> Bool {
        guard let model = itemController.model(for: itemId) else { return false }
        return model.entries.contains(where: { $0.entryId == entryId })
    }

    @MainActor func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? {
        guard module == .table else { return nil }
        return SheetController(itemController: itemController).sheet(for: itemId, level: level)
    }
}
