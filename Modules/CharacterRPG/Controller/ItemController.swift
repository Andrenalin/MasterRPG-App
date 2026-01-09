// @copyright André Trettin

import CoreRPG
import Foundation
import TableRPG

struct ItemController: Sendable {
    @MainActor init(config: ModuleConfiguration, tableRoot: TableRootModel, dataController: DataController?, linkRegisterControllable: LinkRegisterControllable) {
        self.config = config
        
        self.dataControllable = dataController
        self.linkRegisterController = linkRegisterControllable
        
        self.itemDataModel = ItemDataModel(categoryTags: config.categoryTags)
        self.collectionCategory = config.collectionCategory

        self.tableRoot = tableRoot
    }

    let config: ModuleConfigurable
    let collectionCategory: ItemListCategory
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let linkRegisterController: LinkRegisterControllable

    let tableRoot: TableRootModel
}

extension ItemController: ItemControllable {
    typealias Model = ValueModel
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable { linkRegisterController }
}

extension ItemController {
    @MainActor func children(itemId: UUID) -> [Model] {
        guard let parent = itemSync(for: itemId) else { return [] }
        return parent.entries.compactMap(\.valueId).flatMap {
            subchildren(itemId: $0, deep: 1)
        }
    }
    
    @MainActor private func subchildren(itemId: UUID, deep: Int) -> [Model] {
        guard deep < 25, let parent = itemSync(for: itemId) else { return [] }
        return [parent] + parent.entries.compactMap(\.valueId).flatMap {
            subchildren(itemId: $0, deep: deep + 1)
        }
    }
    
    // TODO: move to editController?
    func duplicate(itemId: UUID, withCopy: Bool = true) async -> UUID {
        let (duplicates, copyId, mapper) = await duplicateSubValue(id: itemId, withCopy: withCopy)
        //await root.linkController.repairDuplicateLinks(models: duplicates, mapper: mapper)
        for duplicate in duplicates {
            await replace(model: duplicate, isInsert: true, shouldRepairLinks: true)
        }
        return copyId
    }

    @MainActor
    private func duplicateSubValue(id: UUID, withCopy: Bool) -> ([ValueModel], UUID, [UUID: UUID]) {
        guard let item = itemSync(for: id) else { return ([], id, [:]) }
        
        var duplicates: [ValueModel] = []
        let copyItem: ValueModel = withCopy ? item.duplicate() : item.duplicateWithoutCopy()
        duplicates.append(copyItem)
        
        var mapper: [UUID: UUID] = [id: copyItem.id]
        let subValueIds = item.duplicateSubValueIds()
        subValueIds.forEach {
            let (newDuplicates, newCopyId, newMapper) = duplicateSubValue(id: $0, withCopy: false)
            mapper[$0] = newCopyId
            mapper.merge(newMapper) { first, _ in return first }
            duplicates.append(contentsOf: newDuplicates)
        }
        for (index, entry) in copyItem.entries.enumerated() {
            guard let valueId = entry.valueId else { continue }
            if let copyId = mapper[valueId] {
                copyItem.entries[index].valueId = copyId
                duplicates.first(where: { $0.id == copyId })?.parentId = copyItem.id
            }
        }
        return (duplicates, copyItem.id, mapper)
    }
}
