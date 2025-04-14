// @copyright André Trettin

import AndrenalinKit
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
        guard let rootModel, let item = await itemControllable.item(for: rootModel.itemId) as? SpaceModel else { return }

        if item.entries.isEmpty {
            // group them
            let entries = models.map { SpaceEntryModel(id: UUID(), spaceId: $0.itemId) }
            item.entries = entries
            for entry in item.entries {
                if let space = await itemControllable.item(for: entry.spaceId) as? SpaceModel {
                    space.displayState = DisplayStateMask.groupHidden.set(on: space.displayState)
                    await itemControllable.replace(model: space, isInsert: false, shouldRepairLinks: true)
                }
            }
        } else {
            // ungroup them
            for entry in item.entries {
                if let subSpace = await itemControllable.item(for: entry.spaceId) as? SpaceModel {
                    subSpace.displayState = DisplayStateMask.groupHidden.reset(on: subSpace.displayState)
                    await itemControllable.replace(model: subSpace, isInsert: false, shouldRepairLinks: true)
                }
            }
            item.entries = []
        }
        await itemControllable.replace(model: item, isInsert: false, shouldRepairLinks: true)
    }
}
