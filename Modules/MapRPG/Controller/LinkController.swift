// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import os.log
import AudioRPG
import DiceRPG
import PhotoRPG
import TableRPG
import CharacterRPG

struct LinkController: Sendable {
    let root: MapRootModel
    let audioRoot: AudioRootModel
    let diceRoot: DiceRootModel
    let photoRoot: PhotoRootModel
    let tableRoot: TableRootModel
    let characterRoot: CharacterRootModel
    let itemController: ItemController

    public var itemControllable: any ItemControllable { itemController }
}

extension LinkController: LinkControllable {
    @MainActor public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            }
            if command == LinkType.show.rawValue {
                Task { @MainActor in
                    await toggler?(itemId, itemControllable.config.module)
                }
                return text
            }
            Task { @MainActor in
                await shareResult?.networkActions?.shareId(root.gameController.shareMap(id: itemId))
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task { @MainActor in
                    await toggler(itemId, itemController.config.module)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.config.module)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
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
            result = photoRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = tableRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = characterRoot.linkControllable.repairLink(link, for: result, for: [.all])
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }
    
    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), inspectedItem.displayState != 2, let replacedItem = itemController.copy(of: itemId) else { return }

        for entry in inspectedItem.entries {
            var validatedEntry = entry
            
            let links = entry.links(for: entry.content)
            validatedEntry.content = repairLinks(links, in: validatedEntry.content)
            
            if !entry.isSame(validatedEntry) {
                replacedItem[entry.id]  = validatedEntry
            }
        }
        if !replacedItem.isSame(inspectedItem) {
            Logger.linkController.info("Map: \(replacedItem.name, privacy: .public) will be replaced from reparing links.")
            itemController.replace(model: replacedItem, isInsert: false)
        }
        
        defer { resetLinkRegister(replacedItem) }

        guard let photoId = inspectedItem.photoId, let replacedItem = itemController.copy(of: itemId) else { return }
        if photoRoot.linkControllable.validateLink(itemId: photoId) {
            Task {
                await root.editController.resetImageSize(photoId: photoId, updateModel: replacedItem, save: true)
            }
        } else {
            Logger.linkController.warning("Map: \(replacedItem.name, privacy: .public) --> Photo \(photoId, privacy: .public) is gone. Reset PhotoId, no recovery possible.")
            replacedItem.photoId = nil
            itemController.replace(model: replacedItem, isInsert: false)
        }
    }
}

extension LinkController {
    @MainActor
    func link(for module: NetworkModules) -> [LinkEntryModel] {
        itemController.itemDataModel.items.map { itemController.itemOrEmpty(for: $0) }.sorted(by: { $0.name.count > $1.name.count })
            .map { LinkEntryModel(reference: $0.name, markdownUrl: $0.url(linkNumber: 0)) }
    }
    
    @MainActor
    func linkEntries(for itemId: UUID) -> [LinkEntryModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        return itemController.itemOrEmpty(for: itemId).entries
            .sorted(by: { $0.name.count > $1.name.count })
            .map { LinkEntryModel(reference: $0.name, markdownUrl: item.url(linkNumber: 0, entryId: $0.id)) }
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
            let links = $0.links(for: $0.content)
            links.forEach {
                switch $0.module {
                case .photo:
                    photoIds.append($0.itemId)
                case .value:
                    photoIds.append(contentsOf: characterRoot.linkControllable.collectLinks(of: module, from: $0.itemId))
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
