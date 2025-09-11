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
    @MainActor public func toggleTextLink(model: LinkDataModel, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) -> Void)?, editAction: ((LinkDataModel) -> Bool)?) -> String {
        let itemId = model.sourceId
        let entryId = model.sourceEntryId
        let module = model.sourceModule
        
        if let command {
            if command == LinkType.remove.rawValue {
                if let editAction, editAction(model)  {
                    return text.toggleLink(url: model.url, with: "", remove: true)
                }
                return text
            }
            if command == LinkType.roll.rawValue {
//                root.gameController.rollDice(itemId: itemId, networkActions: shareResult?.networkActions, resultCategopry: nil, rollSynced: true)
//                let toggleText = root.gameController.resultText(itemId: itemId)
                let toggleText = "Kein Result"
                let rollUrl = specialLink(linkType: .roll, model: model)
                return text.toggleLink(url: rollUrl, with: toggleText, replace: true)
            }
            if command == LinkType.show.rawValue {
                toggler?(itemId, module)
            } else {
                // send
//                Task { @MainActor in
//                    if let shareResult, let result = try? await root.gameController.createGameData(for: itemId, resultCategory: shareResult.resultCategory) {
//                        shareResult.networkActions?.game(result, .show)
//                    }
//                }
            }
            return text
        } else {
            if let toggler, entryId == nil {
                toggler(itemId, module)
            }
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? specialLink(linkType: .share, model: model) : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, model: model))" : ""
            let editLine = editAction != nil
            let removeAction = editLine ? " \(specialLink(linkType: .remove, model: model))" : ""
            let result = "\(sendAction)\(showAction)\(specialLink(linkType: .roll, model: model))\(removeAction)"
            let url = model.url
            return text.toggleLink(url: url, with: result)
        }
    }
    
    @MainActor func validate(itemId: UUID, entryId: UUID?) -> Bool {
        itemController.model(for: itemId) != nil
    }
}
