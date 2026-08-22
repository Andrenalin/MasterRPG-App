// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import PdfRPG
import SwiftUI
import os.log

struct LinkController: Sendable {
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let itemController: ItemController
    let gameController: GameController

    public var itemControllable: any ItemControllable { itemController }
}

extension LinkController: LinkControllable {
    @MainActor public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            switch command {
            case LinkType.remove.rawValue:
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            case LinkType.generate.rawValue:
                shareResult?.generationAction(itemId)
            case LinkType.show.rawValue:
                Task {
                    await toggler?(itemId, itemControllable.config.module)
                }
            case LinkType.share.rawValue:
                Task {
                    await shareResult?.networkActions?.shareId(gameController.share(id: itemId))
                }
            default:
                break
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task {
                    await toggler(itemId, itemControllable.config.module)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId) : ""
            let generateAction = ((shareResult?.showGame ?? false) && (shareResult?.generationAction.isEnabled ?? false)) ? specialLink(linkType: .generate, linkNumber: linkNumber, itemId: itemId, entryId: entryId) : ""
            let showAction = (toggler != nil && entryId != nil) ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.config.module)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let description: String
            if let entryId {
                description = item[entryId].content
            } else {
                description = formatInlineDescription(description: item.description, entryCount: item.entries.count)
            }
            let result = "\(sendAction)\(generateAction)\(showAction) \(description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        var result = content
        for link in links {
            result = diceRoot.linkControllable.repairLink(link, for: result, for: [.table])
            result = pdfRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }

    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), inspectedItem.displayState != 2, let replacedItem = itemController.copy(of: itemId) else { return }

        if let diceId = replacedItem.diceId {
            if !diceRoot.linkControllable.validateLink(itemId: diceId) {
                Logger.linkController.warning("Table: \(replacedItem.name, privacy: .public) --> Dice \(diceId, privacy: .public) is gone. Reset DiceId, no recovery possible.")
                replacedItem.diceId = nil
            }
        }

        for entry in inspectedItem.entries {
            var validatedEntry = entry

            let links = entry.links(for: entry.content)
            validatedEntry.content = repairLinks(links, in: validatedEntry.content)

            if !entry.isSame(validatedEntry) {
                replacedItem[entry.id]  = validatedEntry
            }
        }
        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Table: \(replacedItem.name, privacy: .public) will be replaced from repairing links.")
            itemController.replace(model: replacedItem, isInsert: false)
        }
        resetLinkRegister(replacedItem)
    }
}

extension LinkController {
    @MainActor
    func link(for name: String, entryName: String?) -> String? {
        guard let itemId = itemController.itemDataModel.items.first(where: { itemController.nameSync(itemId: $0) == name }) else { return nil }
        let item = itemController.itemOrEmpty(for: itemId)
        if let entryName = entryName {
            guard let entry = item.entries.first(where: { $0.name == entryName }) else { return nil }
            return item.url(linkNumber: 0, entryId: entry.id)
        } else {
            return item.url(linkNumber: 0)
        }
    }
}

extension LinkController {
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] {
        guard let item = itemController.itemSync(for: itemId) else { return [] }
        var photoIds: [UUID] = []
        item.entries.forEach {
            let links = $0.links(for: $0.content)
            links.forEach {
                switch $0.module {
                case .photo:
                    photoIds.append($0.itemId)
                case .dice:
                    photoIds.append(contentsOf: diceRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .pdf:
                    photoIds.append(contentsOf: pdfRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                default:
                    break
                }
            }
        }
        return Array(Set(photoIds))
    }
}
