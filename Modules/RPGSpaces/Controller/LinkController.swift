// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftUI

public struct LinkController: Sendable {
    weak var root: SpaceRoot!
    
    public var itemControllable: any ItemControllable {
        root.itemController as ItemController
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
                if shareResult.gameModus == .master {
                    await shareResult.networkActions?.shareId(root.gameController.share(id: itemId))
                } else {
                    if let result = try? await root.gameController.createGameData(for: itemId) {
                        shareResult.networkActions?.game(result, .generic)
                    }
                }
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task { @MainActor in
                    await toggler(itemId, root.itemController.itemDataModel.networkModule)
                }
            }
            let item = root.itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let showAction = toggler != nil ? " \(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: root.itemController.itemDataModel.networkModule)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let result = "\(sendAction)\(showAction) \(item.description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor
    public func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        guard let entryId else { return itemControllable.itemOrEmpty(for: itemId).url(linkNumber: linkNumber) }
        return root.itemController.itemOrEmpty(for: entryId).url(linkNumber: linkNumber)
    }
}
