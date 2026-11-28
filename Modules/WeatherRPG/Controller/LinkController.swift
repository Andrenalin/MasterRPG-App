// @copyright André Trettin

import CoreRPG
import Foundation
import PhotoRPG
import SwiftUI
import os.log

struct LinkController: Sendable {
    let photoRoot: PhotoRootModel
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
            LinkActionTasks.run {
                await shareResult?.networkActions?.shareId(gameController.share(id: itemId))
            }
            return text
        } else {
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let removeAction = autoToggleAndRemoveAction(linkNumber: linkNumber, itemId: itemId, entryId: entryId, toggler: toggler, editAction: editAction, removeActionSpacing: "")
            let result = "\(sendAction)\(showAction) \(item.description) \(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor public func validateLinks(on itemId: UUID) {
        repairItemLinks(itemId: itemId, as: WeatherModel.self) { inspectedItem in
            let replacedItem = inspectedItem.copy()
            if let photoId = replacedItem.photoId {
                if !photoRoot.linkControllable.validateLink(itemId: photoId) {
                    Logger.linkController.warning("Weather: \(replacedItem.name, privacy: .private) --> Photo \(photoId, privacy: .public) is gone. Reset PhotoId, no recovery possible.")
                    replacedItem.photoId = nil
                }
            }
            return replacedItem
        }
    }
}

extension LinkController {
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] {
        guard let item = itemController.itemSync(for: itemId) else { return [] }
        if let id = item.photoId {
            return [id]
        }
        return []
    }
}
