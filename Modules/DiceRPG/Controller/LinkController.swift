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
    @MainActor public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if let handled = standardCommand(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command, in: text, toggler: toggler) {
                return handled
            }
            if command == LinkType.roll.rawValue {
                gameController.rollDice(itemId: itemId, networkActions: shareResult?.networkActions, resultCategory: nil, rollSynced: true)
                let rollUrl = specialLink(linkType: .roll, linkNumber: linkNumber, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: rollUrl, with: gameController.resultText(itemId: itemId), replace: true)
            }
            guard command == LinkType.share.rawValue else { return text }
            LinkActionTasks.run {
                guard let shareResult else { return }
                // A failed share is logged by `LinkActionTasks`. See CODE_AUDIT §5.8.
                let result = try await gameController.createGameData(for: itemId, resultCategory: shareResult.resultCategory)
                shareResult.networkActions?.game(result, .show, nil)
            }
            return text
        } else {
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.config.module)) ?? false
            let removeAction = editLine ? "\(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let result = "\(sendAction)\(showAction)\(specialLink(linkType: .roll, linkNumber: linkNumber, itemId: itemId, entryId: entryId))\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        repairingOwnModuleLinks(links, in: content)
    }

    @MainActor public func validateLinks(on itemId: UUID) {
        repairItemLinks(itemId: itemId, as: DiceModel.self) { inspectedItem in
            let replacedItem = inspectedItem.copy()
            // Entries are single-child references (`ChildEntryModel`) with no free-text `content`
            // of their own to repair — only the item's own `description` can embed a link.
            replacedItem.description = repairLinks(LinkReplaceController.links(for: inspectedItem.description), in: inspectedItem.description)
            return replacedItem
        }
    }

    @MainActor public func link(for name: String, entryName: String?) -> String? {
        guard let itemId = itemController.itemDataModel.items.first(where: { itemController.itemSync(for: $0)?.name == name }) else { return nil }
        return itemController.itemOrEmpty(for: itemId).url(linkNumber: 0)
    }
}
