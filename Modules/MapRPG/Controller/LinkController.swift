// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import os.log
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import TableRPG
import CharacterRPG

struct LinkController: Sendable {
    let root: MapRootModel
    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let pdfRoot: PdfRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let itemController: ItemController

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
                await shareResult?.networkActions?.shareId(root.gameController.shareMap(id: itemId))
            }
            return text
        } else {
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let removeAction = autoToggleAndRemoveAction(linkNumber: linkNumber, itemId: itemId, entryId: entryId, toggler: toggler, editAction: editAction)
            let description: String
            if let entryId {
                description = item[entryId].content
            } else {
                description = formatInlineDescription(description: item.description, entryCount: item.entries.count)
            }
            let result = "\(sendAction)\(showAction) \(description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        var result = content
        for link in links {
            result = audioRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = diceRoot.linkControllable.repairLink(link, for: result, for: [.rules, .table, .value])
            result = pdfRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = photoRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = tableRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = characterRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }

    @MainActor public func validateLinks(on itemId: UUID) {
        // A photo that is gone is a dead reference in the library too: cleared like a dead link,
        // although the map's content is otherwise memory-only during a game.
        repairItemLinks(itemId: itemId, as: MapModel.self) { inspectedItem in
            let replacedItem = inspectedItem.copy()
            for entry in inspectedItem.entries {
                var validatedEntry = entry

                let links = LinkReplaceController.links(for: entry.content)
                validatedEntry.content = repairLinks(links, in: validatedEntry.content)

                if !entry.isSame(validatedEntry) {
                    replacedItem[entry.id]  = validatedEntry
                }
            }
            if let photoId = replacedItem.photoId, !photoRoot.linkControllable.validateLink(itemId: photoId) {
                Logger.linkController.warning("Map: \(replacedItem.name, privacy: .private) --> Photo \(photoId, privacy: .private) is gone. Reset PhotoId, no recovery possible.")
                replacedItem.photoId = nil
            }
            return replacedItem
        }

        guard let photoId = itemController.itemSync(for: itemId)?.photoId,
              photoRoot.linkControllable.validateLink(itemId: photoId),
              let replacedItem = itemController.copy(of: itemId) else { return }
        LinkActionTasks.run {
            await root.editController.resetImageSize(photoId: photoId, updateModel: replacedItem, save: true)
        }
    }
}

extension LinkController {
    @MainActor func collectLinks(of module: NetworkModules, from itemId: UUID) -> [UUID] {
        guard let item = itemController.itemSync(for: itemId) else { return [] }
        var photoIds: [UUID] = []
        if let id = item.photoId {
            photoIds.append(id)
        }
        item.entries.forEach {
            let links = LinkReplaceController.links(for: $0.content)
            links.forEach {
                switch $0.module {
                case .photo:
                    photoIds.append($0.itemId)
                case .value:
                    photoIds.append(contentsOf: characterRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .audio:
                    photoIds.append(contentsOf: audioRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .dice:
                    photoIds.append(contentsOf: diceRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .pdf:
                    photoIds.append(contentsOf: pdfRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                case .table:
                    photoIds.append(contentsOf: tableRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
                default:
                    break
                }
            }
        }
        item.mapPins.forEach {
            if let id = $0.photoId {
               photoIds.append(id)
            }
            if let characterId = $0.characterId {
                photoIds.append(contentsOf: characterRoot.linkControllable.collectLinks(of: module, from: characterId))
            }
        }
        return Array(Set(photoIds))
    }
}
