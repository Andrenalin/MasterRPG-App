// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

public struct LinkController: Sendable {
    init(itemController: ItemController, gameController: GameController) {
        self.itemController = itemController
        self.gameController = gameController
    }
    let itemController: ItemController
    let gameController: GameController
    
    public var itemControllable: any ItemControllable {
        itemController
    }
}

extension LinkController: LinkControllable {
    @MainActor
    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            }
            if command == LinkType.show.rawValue {
                Task { @MainActor in
                    await toggler?(itemId, itemControllable.itemDataModel.networkModule)
                }
                return text
            }
            guard let shareResult else { return text }
            Task { @MainActor in
                if command == LinkType.share.rawValue {
                    if shareResult.gameModus == .master {
                        await shareResult.networkActions?.shareId(gameController.share(id: itemId))
                    } else {
                        if let result = try? await gameController.createGameData(for: itemId) {
                            shareResult.networkActions?.game(result, .generic)
                        }
                    }
                } else {
                    if let result = try? await gameController.createGameData(for: itemId) {
                        shareResult.networkActions?.game(result, .photoSpace)
                    }
                }
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task { @MainActor in
                    await toggler(itemId, itemControllable.itemDataModel.networkModule)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId))  \(specialLink(linkType: .photoImmersive, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.itemDataModel.networkModule)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let result = "\(sendAction)\(showAction) \(item.description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor
    public func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        guard let entryId else { return itemControllable.itemOrEmpty(for: itemId).url(linkNumber: linkNumber) }
        return itemControllable.itemOrEmpty(for: entryId).url(linkNumber: linkNumber)
    }
    
    @MainActor public func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel? {
        guard module == itemController.itemDataModel.networkModule, let model = itemController.itemSync(for: itemId) else { return nil }
        let entry = SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.itemDataModel.networkModule), level: level, type: .photo, name: "", description: "", entries: [])
        return SheetModel(source: ItemRowModel(itemId: itemId, typeId: itemController.itemDataModel.networkModule), level: level, type: .item, name: model.name, description: model.description, entries: [entry])
    }
}
