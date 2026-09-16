// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import os.log

struct LinkController: Sendable {
    let itemController: ItemController
    let gameController: GameController

    public var itemControllable: any ItemControllable { itemController }
}

extension LinkController: LinkControllable {
    @MainActor
    public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if let handled = standardCommand(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command, in: text, toggler: toggler) {
                return handled
            }
            guard command == LinkType.share.rawValue else { return text }
            guard let shareResult else { return text }
            Task {
                if shareResult.gameModus == .master {
                    await shareResult.networkActions?.shareId(gameController.share(id: itemId))
                } else {
                    if let result = try? await gameController.createGameData(for: itemId) {
                        shareResult.networkActions?.game(result, .generic, nil)
                    }
                }
            }
            return text
        } else {
            let item = itemController.itemOrEmpty(for: itemId)
            return standardToggleResult(linkNumber: linkNumber, itemId: itemId, entryId: entryId, in: text, shareResult: shareResult, toggler: toggler, editAction: editAction, description: item.description)
        }
    }

    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        var result = content
        for link in links {
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }

    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), inspectedItem.displayState != 2, let replacedItem = itemController.copy(of: itemId) else { return }

        // Entries are single-child references (`PhotoEntryModel`) with no free-text `content`
        // of their own to repair — only the item's own `description` can embed a link.
        replacedItem.description = repairLinks(LinkReplaceController.links(for: inspectedItem.description), in: inspectedItem.description)

        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Photo: \(replacedItem.name, privacy: .private) will be replaced from repairing links.")
            itemController.replace(model: replacedItem, isInsert: false)
        }
        resetLinkRegister(replacedItem)
    }
}
