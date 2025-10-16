// @copyright André Trettin

import AndrenalinKit
import Foundation
import CoreData
import RPGTables

struct ItemController: Sendable {
    @MainActor
    init(root: ValueRoot, dataController: DataController?, tableChildren: (@MainActor @Sendable (ItemRowModel) -> [ItemRowModel])? = nil) {
        self.root = root
        self.dataControllable = dataController
        itemDataModel = ItemDataModel(categoryTags: [.character, .gameMaster, .item, .monster], networkModule: .value)
        self.tableChildren = tableChildren
    }

    weak var root: ValueRoot!
    let collectionCategory: ItemListCategory = .collection
    let dataControllable: (any DataPersistenceControllable)?
    let itemDataModel: ItemDataModel
    let tableChildren: (@MainActor @Sendable (ItemRowModel) -> [ItemRowModel])?
}

extension ItemController: ItemControllable {
    typealias Model = ValueModel
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable {
        root.rootControllable.linkRegisterControllable
    }
    
    @MainActor
    func children(for model: ItemRowModel) -> [ItemRowModel] {
        switch model.typeId {
        case .table:
            if let tableChildren {
                return tableChildren(model)
            }
            return root.tableRoot.itemControllable.children(for: model)
        default:
            let item = itemOrEmpty(for: model.itemId)
            return item.entries.flatMap {
                var entries = [ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: itemDataModel.networkModule)]
                if item.quickEditEntries.contains($0.id) {
                    let edit = ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: NetworkModules.editor)
                    entries.append(edit)
                }
                return entries
            }
        }
    }

    @MainActor
    func childrenTree(for model: ItemRowModel) -> ItemRowModel? {
        guard model.typeId == itemDataModel.networkModule, let entryId = model.entryId, let valueId = itemOrEmpty(for: model.itemId)[entryId].valueId else { return nil }
        return ItemRowModel(itemId: valueId, typeId : itemDataModel.networkModule)
    }

    func didDelete(model: ModelType) async {
        guard let model = model as? ValueModel else { return }
        await root.applyToAllEditController {
            await $0.didDelete(itemId: model.id)
        }
        for entry in model.entries {
            await root.editController(type: .main).remove(entryId: entry.id, from: model, isDeepRemove: true)
        }
    }
    
    func didUpdate(model: ModelType) async {
        guard let model = model as? Model else { return }
        await root.applyToAllEditController {
            await $0.didUpdate(item: model)
        }
    }

    func duplicate(itemId: UUID) async -> UUID {
        await duplicate(itemId: itemId, withCopy: true)
    }

    func duplicate(itemId: UUID, withCopy: Bool) async -> UUID {
        let (duplicates, copyId, mapper) = await duplicateSubValue(id: itemId, withCopy: withCopy)
        await root.linkController.repairDuplicateLinks(models: duplicates, mapper: mapper)
        for duplicate in duplicates {
            await replace(model: duplicate, isInsert: true, shouldRepairLinks: true)
        }
        return copyId
    }
    
    @MainActor
    func itemTree(from rootModel: ItemRowModel?, to childModel: ItemRowModel) -> [ItemRowModel] {
        guard let rootModel else {
            for itemId in itemDataModel.items {
                let model = ItemRowModel(itemId: itemId, typeId: itemDataModel.networkModule)
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
        return filter(model: ItemRowModel(itemId: valueId, typeId: itemDataModel.networkModule), search: search, isHidden: isHidden, filterTags: filterTags, deep: deep + 1)
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
                return [ItemRowModel(itemId: item.id, entryId: entry.id, typeId: itemDataModel.networkModule)]
            }
            return itemTree(from: ItemRowModel(itemId: valueId, typeId: itemDataModel.networkModule), to: childModel)
        }
    }
}
