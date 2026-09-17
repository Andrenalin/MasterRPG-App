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
            guard command == LinkType.share.rawValue else { return text }
            guard let shareResult else { return text }
            Task {
                if shareResult.gameModus == .master {
                    await shareResult.networkActions?.shareId(gameController.share(id: itemId))
                } else {
                    do {
                        let result = try await gameController.createGameData(for: itemId)
                        shareResult.networkActions?.game(result, .generic, nil)
                    } catch {
                        Logger.linkController.error("Failed to create game data for \(itemId, privacy: .public): \(error.localizedDescription, privacy: .public)")
                    }
                }
            }
            return text
        } else {
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let showAction = (toggler != nil && entryId != nil) ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let removeAction = autoToggleAndRemoveAction(linkNumber: linkNumber, itemId: itemId, entryId: entryId, toggler: toggler, editAction: editAction)
            var description = item.description
            if let entryId {
                description = item[entryId].content
            }
            let result = "\(sendAction)\(showAction) \(description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
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

        replacedItem.description = repairLinks(LinkReplaceController.links(for: inspectedItem.description), in: inspectedItem.description)

        for entry in inspectedItem.entries {
            var validatedEntry = entry
            let links = LinkReplaceController.links(for: entry.content)
            validatedEntry.content = repairLinks(links, in: validatedEntry.content)
            if !entry.isSame(validatedEntry) {
                replacedItem[entry.id] = validatedEntry
            }
        }
        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Pdf: \(replacedItem.name) will be replaced from repairing links.")
            itemController.replace(model: replacedItem, isInsert: false)
        }
        resetLinkRegister(replacedItem)
    }
}
