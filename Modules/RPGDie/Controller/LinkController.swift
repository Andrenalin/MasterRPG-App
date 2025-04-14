// @copyright André Trettin

import AndrenalinKit
import Foundation
import SwiftUI

public struct LinkController: Sendable {
    weak var root: DiceRoot!
    let itemController: ItemController

    public var itemControllable: any ItemControllable {
        itemController as ItemController
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
            if command == LinkType.roll.rawValue {
                root.gameController.rollDice(itemId: itemId, networkActions: shareResult?.networkActions, resultCategopry: nil, rollSynced: true)
                let rollUrl = specialLink(linkType: .roll, linkNumber: linkNumber, itemId: itemId, entryId: entryId)
                return text.toggleLink(url: rollUrl, with: root.gameController.resultText(itemId: itemId), replace: true)
            }
            if command == LinkType.show.rawValue {
                Task { @MainActor in
                    await toggler?(itemId, itemControllable.itemDataModel.networkModule)
                }
                return text
            }
            // send
            Task { @MainActor in
                if let shareResult, let result = try? await root.gameController.createGameData(for: itemId, resultCategory: shareResult.resultCategory) {
                    shareResult.networkActions?.game(result, .show)
                }
            }
            return text
        } else {
            let sendAction = ((shareResult?.showGame ?? false) && shareResult?.networkActions != nil) ? "\(specialLink(linkType: .share, linkNumber: linkNumber, itemId: itemId, entryId: entryId)) " : ""
            let showAction = toggler != nil ? "\(specialLink(linkType: .show, linkNumber: linkNumber, itemId: itemId, entryId: entryId)) " : ""
            let editLine = editAction?(ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemController.itemDataModel.networkModule)) ?? false
            let removeAction = editLine ? " \(specialLink(linkType: .remove, linkNumber: linkNumber, itemId: itemId, entryId: entryId))" : ""
            let result = "\(sendAction)\(showAction)\(specialLink(linkType: .roll, linkNumber: linkNumber, itemId: itemId, entryId: entryId))\(removeAction)"
            let url = generateLink(linkNumber: linkNumber, itemId: itemId, entryId: entryId)
            return text.toggleLink(url: url, with: result)
        }
    }

    @MainActor
    public func generateLink(linkNumber: Int, itemId: UUID, entryId: UUID?) -> String {
        guard let entryId else { return itemControllable.itemOrEmpty(for: itemId).url(linkNumber: linkNumber) }
        return itemControllable.itemOrEmpty(for: entryId).url(linkNumber: linkNumber)
    }

    @MainActor
    public func link(for name: String, entryName: String?) -> String? {
        guard let itemId = itemController.itemDataModel.items.first(where: { itemController.itemSync(for: $0)?.name == name }) else { return nil }
        return itemController.itemOrEmpty(for: itemId).url(linkNumber: 0)
    }

    @MainActor
    public func link(for module: NetworkModules) -> [LinkEntryModel] {
        let category: ItemListCategory
        switch module {
        case .table: category = .table
        case .value: category = .value
        default: category = .all
        }
        
        var items = itemController.itemDataModel.items.map { itemController.itemOrEmpty(for: $0) }
        if category != .all {
            items = items.filter { $0.category == category }
        }
        return items.sorted(by: { $0.name.count > $1.name.count })
            .map { LinkEntryModel(reference: $0.name, markdownUrl: $0.url(linkNumber: 0)) }
    }

    @MainActor
    public func linkEntries(for itemId: UUID) -> [LinkEntryModel] {
        [LinkEntryModel(reference: itemController.itemOrEmpty(for: itemId).name, markdownUrl: itemController.itemOrEmpty(for: itemId).url(linkNumber: 0))]
    }
}
