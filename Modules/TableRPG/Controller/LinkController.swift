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
            if let handled = standardCommand(linkNumber: linkNumber, itemId: itemId, entryId: entryId, command: command, in: text, toggler: toggler) {
                return handled
            }
            switch command {
            case LinkType.generate.rawValue:
                shareResult?.generationAction(itemId)
            case LinkType.share.rawValue:
                // Fire-and-forget is intentional here: `share(id:)` and
                // `shareId` cannot throw, and the call site is a synchronous
                // text-link toggle with nowhere to hold a cancellable Task
                // handle. See CODE_AUDIT_Table §3.3.
                Task {
                    await shareResult?.networkActions?.shareId(gameController.share(id: itemId))
                }
            default:
                break
            }
            return text
        } else {
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId) : ""
            let generateAction = ((shareResult?.showGame ?? false) && (shareResult?.generationAction.isEnabled ?? false)) ? specialLink(linkType: .generate, linkNumber: linkNumber, itemId: itemId, entryId: entryId) : ""
            let showAction = (toggler != nil && entryId != nil) ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let removeAction = autoToggleAndRemoveAction(linkNumber: linkNumber, itemId: itemId, entryId: entryId, toggler: toggler, editAction: editAction)
            let description: String
            if let entryId {
                description = item[entryId].content
            } else {
                description = formatInlineDescription(description: item.description, entryCount: item.entries.count)
            }
            let result = "\(generateAction)\(sendAction)\(showAction) \(description)\(removeAction)"
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
        guard let inspectedItem = itemController.itemSync(for: itemId), !inspectedItem.isHidden, let replacedItem = itemController.copy(of: itemId) else { return }

        if let diceId = replacedItem.diceId {
            if !diceRoot.linkControllable.validateLink(itemId: diceId) {
                Logger.linkController.warning("Table: \(replacedItem.name, privacy: .private) --> Dice \(diceId, privacy: .public) is gone. Reset DiceId, no recovery possible.")
                replacedItem.diceId = nil
            }
        }

        for entry in inspectedItem.entries {
            var validatedEntry = entry

            let links = LinkReplaceController.links(for: entry.content)
            validatedEntry.content = repairLinks(links, in: validatedEntry.content)

            if !entry.isSame(validatedEntry) {
                replacedItem[entry.id]  = validatedEntry
            }
        }
        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Table: \(replacedItem.name, privacy: .private) will be replaced from repairing links.")
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
        collectLinks(of: module, from: itemId, visitedTableIds: [])
    }

    // Tables may legitimately link to other tables (a random encounter
    // table rolling on itself is a normal loop, mirroring
    // `TableGenerationController.maxTableRecursionCount`), so photo/dice/pdf
    // links nested behind a chain of table links must still be followed —
    // recursing into this same module's own LinkController, guarded by
    // `visitedTableIds` so a table cycle can't recurse forever.
    // See CODE_AUDIT_Table §5.4.
    @MainActor private func collectLinks(of module: NetworkModules, from itemId: UUID, visitedTableIds: Set<UUID>) -> [UUID] {
        guard let item = itemController.itemSync(for: itemId) else { return [] }
        let visitedTableIds = visitedTableIds.union([itemId])
        var collectedIds: [UUID] = []
        item.entries.forEach {
            let links = LinkReplaceController.links(for: $0.content)
            links.forEach {
                switch $0.module {
                case .photo:
                    collectedIds.append($0.itemId)
                case .dice:
                    collectedIds.append(contentsOf: diceRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .pdf:
                    collectedIds.append(contentsOf: pdfRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .table:
                    guard !visitedTableIds.contains($0.itemId) else { break }
                    collectedIds.append(contentsOf: collectLinks(of: module, from: $0.itemId, visitedTableIds: visitedTableIds))
                default:
                    break
                }
            }
        }
        return Array(Set(collectedIds))
    }
}
