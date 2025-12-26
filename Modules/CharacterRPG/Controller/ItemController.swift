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
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable {
        linkRegisterController
    }

    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        let item = itemOrEmpty(for: model.itemId)
        return item.entries.flatMap {
            var entries = [ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: config.module)]
            if item.quickEditEntries.contains($0.id) {
                let edit = ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: NetworkModules.editor)
                entries.append(edit)
            }
            return entries
        }
    }

    @MainActor
    func childrenTree(for model: ItemRowModel) -> ItemRowModel? {
        guard model.typeId == config.module, let entryId = model.entryId, let valueId = itemOrEmpty(for: model.itemId)[entryId].valueId else { return nil }
        return ItemRowModel(itemId: valueId, typeId: config.module)
    }

    func didDelete(model: ModelType) async {
        guard let model = model as? ValueModel else { return }
//        for entry in model.entries {
//            await root.editController.remove(entryId: entry.id, from: model, isDeepRemove: true)
//        }
    }
    
    func didUpdate(model: ModelType) async {
    }

    func duplicate(itemId: UUID) async -> UUID {
        await duplicate(itemId: itemId, withCopy: true)
    }

    func duplicate(itemId: UUID, withCopy: Bool) async -> UUID {
        let (duplicates, copyId, mapper) = await duplicateSubValue(id: itemId, withCopy: withCopy)
        //await root.linkController.repairDuplicateLinks(models: duplicates, mapper: mapper)
        for duplicate in duplicates {
            await replace(model: duplicate, isInsert: true, shouldRepairLinks: true)
        }
        return copyId
    }
    
    @MainActor
    func itemTree(from rootModel: ItemRowModel?, to childModel: ItemRowModel) -> [ItemRowModel] {
        guard let rootModel else {
            for itemId in itemDataModel.items {
                let model = ItemRowModel(itemId: itemId, typeId: config.module)
                let result = itemTree(from: model, to: childModel)
                if !result.isEmpty {
                    return result
                }
            }
            return []
        }
        
        if rootModel.itemId == childModel.itemId {
            return []
        }
        return itemTree(from: rootModel, to: childModel)
    }
    
    @MainActor
    func filterChildren(model: ItemRowModel, search: String, isHidden: Bool, filterTags: [TagFilterSelection], deep: Int) -> ListFilterOptions {
        guard deep < 10, let entryId = model.entryId, let valueId = itemOrEmpty(for: model.itemId)[entryId].valueId else { return .notMatch }
        return filter(model: ItemRowModel(itemId: valueId, typeId: config.module), search: search, isHidden: isHidden, filterTags: filterTags, deep: deep + 1)
    }
}

extension ItemController {
    func duplicate(model: ItemRowModel) async {
        _ = await duplicate(itemId: model.itemId)
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

    @MainActor
    private func itemTree(from rootModel: ItemRowModel, to childModel: ItemRowModel) -> [ItemRowModel] {
        let item = itemOrEmpty(for: rootModel.itemId)
        return item.entries.flatMap { entry -> [ItemRowModel] in
            guard let valueId = entry.valueId else { return [] }
            if valueId == childModel.itemId {
                return [ItemRowModel(itemId: item.id, entryId: entry.id, typeId: config.module)]
            }
            return itemTree(from: ItemRowModel(itemId: valueId, typeId: config.module), to: childModel)
        }
    }
}
