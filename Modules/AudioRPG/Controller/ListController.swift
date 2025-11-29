// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

struct ListController: Sendable {
    init(itemController: ItemController, itemListModel: ListModel) {
        self.itemController = itemController
        self.model = itemListModel
    }

    @MainActor 
    init(itemController: ItemController, listStoreName: LocalizedStringResource, hasChildren: Bool, searchToken: ItemListCategory, categoryTags: [ItemListCategory], selectedItems: [ItemRowTreeModel] = []) {
        self.itemController = itemController
        self.model = ListModel(searchToken: searchToken, categoryTags: [ItemListCategory.all] + categoryTags, listStoreName: String(localized: listStoreName).localizedString, hasChildren: hasChildren)
    }

    let itemController: ItemController
    let model: ListModel
}

extension ListController: ListControllable {
    var itemControllable: any ItemControllable {
        itemController as ItemController
    }
    
    var canGroup: Bool { true }

    func groupItems(for selection: Set<ItemRowTreeModel>) async {
        let (models, rootModel) = await self.selection(for: selection)
        guard let rootModel, let item = await itemControllable.item(for: rootModel.itemId) as? AudioModel else { return }

        if item.entries.isEmpty {
            // group them
            let entries = models.map { AudioEntryModel(id: UUID(), audioId: $0.itemId) }
            item.entries = entries
            for entry in entries {
                if let track = await itemControllable.item(for: entry.audioId) as? AudioModel {
                    track.displayState = DisplayStateMask.groupHidden.set(on: track.displayState)
                    await itemControllable.replace(model: track, isInsert: false, shouldRepairLinks: true)
                }
            }
        } else {
            // ungroup them
            for entry in item.entries {
                if let track = await itemControllable.item(for: entry.audioId) as? AudioModel {
                    track.displayState = DisplayStateMask.groupHidden.reset(on: track.displayState)
                    await itemControllable.replace(model: track, isInsert: false, shouldRepairLinks: true)
                }
            }
            item.entries = []
        }
        await itemControllable.replace(model: item, isInsert: false, shouldRepairLinks: true)
    }
}
