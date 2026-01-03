// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import SwiftUI
import os.log

public struct LinkController: Sendable {
    init(diceRoot: DiceRootModel, itemController: ItemController, gameController: GameController) {
        self.diceRoot = diceRoot
        self.itemController = itemController
        self.gameController = gameController
    }
    let diceRoot: DiceRootModel
    let itemController: ItemController
    let gameController: GameController
    
    public var itemControllable: any ItemControllable {
        itemController
    }
}

extension LinkController: LinkControllable {

    @MainActor public func toggleTextLink(linkNumber: Int, itemId: UUID, entryId: UUID?, command: String?, in text: String, shareResult: ShareValueResult?, toggler: ((UUID, NetworkModules) async -> Void)?, editAction: ((ItemRowModel) -> Bool)?) -> String {
        if let command {
            if command == LinkType.remove.rawValue {
                let url = generateLink(linkNumber: linkNumber - LinkType.remove.linkNumberAddition, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: url, with: name(for: itemId, entryId: entryId), remove: true)
            }
            Task { @MainActor in
                if command == LinkType.show.rawValue {
                    await toggler?(itemId, itemControllable.config.module)
                } else {
                    // command share
                    await shareResult?.networkActions?.shareId(gameController.share(id: itemId))
                }
            }
            return text
        } else {
            if let toggler, entryId == nil, editAction == nil {
                Task { @MainActor in
                    await toggler(itemId, itemControllable.config.module)
                }
            }
            let item = itemController.itemOrEmpty(for: itemId)
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId) : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.config.module)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let description: String
            if let entryId {
                description = item[entryId].content
            } else {
                description = "\(item.name) / \(item.description) / \(item.entries.count) Entries"
            }
            let result = "\(sendAction)\(showAction) \(description)\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }
    
    @MainActor public func repairLinks(_ links: [LinkReplaceModel], in content: String) -> String {
        var result = content
        for link in links {
            result = diceRoot.linkController.repairLink(link, for: result, for: [.table])
            result = repairLink(link, for: result, for: [.all])
        }
        return result
    }
    
    @MainActor public func validateLinks(on itemId: UUID) {
        guard let inspectedItem = itemController.itemSync(for: itemId), let replacedItem = itemController.copy(of: itemId) else { return }
        
        if let diceId = replacedItem.diceId {
            if !diceRoot.linkController.validateLink(itemId: diceId) {
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
            Logger.linkController.info("Table: \(replacedItem.name, privacy: .public) will be replaced from reparing links.")
            itemController.replace(model: replacedItem, isInsert: false, shouldRepairLinks: true)
        }
    }
    
    @MainActor
    public func toggleSheet(itemId: UUID, level: Int, module: NetworkModules) -> SheetModel {
        SheetController(itemController: itemController).sheet(for: itemId, level: level)
    }
}

public extension LinkController {
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
    
    @MainActor
    func link(for module: NetworkModules) -> [LinkEntryModel] {
        itemController.itemDataModel.items.map { itemController.itemOrEmpty(for: $0) }.sorted(by: { $0.name.count > $1.name.count })
            .map { LinkEntryModel(reference: $0.name, markdownUrl: $0.url(linkNumber: 0)) }
    }
    
    @MainActor
    func linkEntries(for itemId: UUID) -> [LinkEntryModel] {
        let item = itemController.itemOrEmpty(for: itemId)
        return item.entries
            .sorted(by: { $0.name.count > $1.name.count })
            .map { LinkEntryModel(reference: $0.name, markdownUrl: item.url(linkNumber: 0, entryId: $0.id)) }
    }
}

// MARK: Other

public extension LinkController {
    @MainActor
    func nameWithEntry(for id: UUID, entryId: UUID?) -> (String, String?) {
        let item = itemController.itemOrEmpty(for: id)
        guard let entryId else {
            return (item.name, nil)
        }
        return (item.name, item[entryId].name)
    }
    
    @MainActor
    func templateItems(for rootId: UUID) -> [ItemRowModel] {
        let item = itemController.itemOrEmpty(for: rootId)
        return item.entries.map { ItemRowModel(itemId: rootId, entryId: $0.id, typeId: itemController.config.module) }
    }
    
//    @MainActor 
//    func generateItems(for rootId: UUID) -> ([ItemRowModel], String) {
//        let generatorStore = root.generatorController(rootItem: ItemRowModel(itemId: rootId, typeId: itemController.config.module))
//        return (generatorStore.roleResults(), generatorStore.entryValue)
//    }
    
    @MainActor
    func generateItem(for tableId: UUID, entryId: UUID) -> (String, String) {
        let item = itemController.itemOrEmpty(for: tableId)
        return (item[entryId].content, item.url(linkNumber: 0, entryId: entryId))
    }
}
