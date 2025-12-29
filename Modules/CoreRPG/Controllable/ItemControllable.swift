// @copyright André Trettin

import Foundation
import Observation

public protocol ItemControllable: Sendable  {
    associatedtype Model: ItemDataAccessable & ItemDiffComparable & ItemDuplicatable & ItemLinkRegistable & Identifiable & Equatable & Hashable & Codable & ModelType
        
    var config: ModuleConfigurable { get }
    var collectionCategory: ItemListCategory { get }
    var dataControllable: (any DataPersistenceControllable)? { get }
    var fileUrlDataController: FileUrlDataController? { get }
    
    @MainActor var linkRegisterControllable: LinkRegisterControllable { get }
    var itemDataModel: ItemDataModel { get }
    
    func didDelete(model: ModelType) async
    func didUpdate(model: ModelType) async
    func duplicate(model: ItemRowModel) async
    func reset(fileUrl: FileUrl?, item: any ItemDataAccessable) async
}

// MARK: - Configuration
public extension ItemControllable {
    var collectionCategory: ItemListCategory { .collection }
    var fileUrlDataController: FileUrlDataController? { nil }
}

// MARK: - Manipulate Model

public extension ItemControllable {
    @MainActor
    func copy(of itemId: UUID) -> Model? {
        self.itemOrEmpty(for: itemId).copy()
    }

    func reset(fileUrl: FileUrl?, item: any ItemDataAccessable) async {}

    func merge(with model: ModelType) async -> ModelType? {
        guard let model = model as? Model, let current = await self.item(for: model.id) else { return model }
        if model.isSame(current) {
            return nil
        }
        return model.merge(current)
    }
    
    func item(for itemId: UUID) async -> Model? {
        await itemDataModel.item(for: itemId) as? Model
    }

    @MainActor
    func itemSync(for itemId: UUID) -> Model? {
        itemDataModel.item(for: itemId) as? Model
    }

    func item(for itemId: UUID, version: Int) async -> Model? {
        let item = await self.item(for: itemId)
        guard version != 0, let item else { return item }
        return item.version == version ? item : nil
    }

    @MainActor
    func itemOrEmpty(for itemId: UUID) -> Model {
        guard let item = self.itemSync(for: itemId) else { return Model.empty(itemId) }
        return item
    }

    @MainActor
    func isEqual(with other: ModelType) -> Bool {
        guard let other = other as? Model, let second = self.itemSync(for: other.id) else { return false }
        return second.isEqual(other: other)
    }

    @MainActor
    func replace(model: ModelType?, isInsert: Bool, shouldRepairLinks: Bool) {
        guard let model = model as? Model else { return }
        if let orignal = self.itemSync(for: model.id) {
            let updateHidden = orignal.isGroupHidden != model.isGroupHidden
            let originalLinkModels = orignal.linkRegisterModels
            var originalEntryIds = Set(orignal.entries.map { $0.id })
            let resort = orignal.name != model.name
            if orignal.replace(with: model) {
                Task {
                    try? await dataControllable?.replace(id: orignal.id, with: orignal)
                }
                let linkModels = orignal.linkRegisterModels
                if originalLinkModels != linkModels {
                    linkRegisterControllable.deregister(links: originalLinkModels)
                    linkRegisterControllable.register(links: linkModels)
                }
                originalEntryIds.subtract(orignal.entries.map { $0.id })
                if shouldRepairLinks {
                    repairLinks(for: originalEntryIds.map { ItemRowModel(itemId: orignal.id, entryId: $0, typeId: config.module) })
                }
                for entryId in originalEntryIds {
                    resetUsedLink(for: ItemRowModel(itemId: orignal.id, entryId: entryId, typeId: config.module))
                }

                if resort {
                    resortItem(changed: orignal)
                }
            }
            if updateHidden {
                itemDataModel.increaseHiddenCounter()
            }
        } else {
            if isInsert {
                Task {
                    try? await dataControllable?.replace(id: model.id, with: model)
                }
            }
            setModel(with: model)
            insertIntoItems(model: model)
        }
        itemDataModel.updateTags(with: model.tags)
    }
    
    @MainActor
    func setModel(with model: ModelType) {
        guard let model = model as? Model else { return }
        let linkModels = model.linkRegisterModels
        linkRegisterControllable.register(links: linkModels)
        itemDataModel.setItem(id: model.id, item: model)
    }

    @MainActor
    func setNewItems(_ newItemData: [Model]) {
        itemDataModel.items = newItemData.map { $0.id }
        newItemData.forEach {
            itemDataModel.itemData[$0.id] = $0
        }
    }

    func decode(data: Data, with decoder: JSONDecoder, version: Int) throws -> Model {
        // default ignore any version numbers. Later a module can handle older version differently.
        try decoder.decode(Model.self, from: data)
    }
    
    @MainActor
    private func resortItem(changed model: Model) {
        guard itemDataModel.removeItem(itemId: model.id) else { return }
        insertIntoItems(model: model)
    }

    func updatesIds(_ itemIds: [UUID]) async {
        let deletedIds = await itemDataModel.items.filter { id in !itemIds.contains { $0 == id } }
        for id in deletedIds {
            await delete(itemId: id)
        }
        for itemId in itemIds {
            guard await itemDataModel.itemData[itemId] != nil else { continue }
            guard let item = try? await dataControllable?.fetch(id: itemId) as? Model else { continue }
            await setModel(with: item)
            await itemDataModel.updateTags(with: item.tags)
            await didUpdate(model: item)
        }
        await itemDataModel.resetItems(itemIds)
    }

    @MainActor func update(model: ModelType?) {
        guard let model = model as? Model else { return }
        if let orignal = self.itemSync(for: model.id) {
            let updateHidden = orignal.isGroupHidden != model.isGroupHidden
            let originalLinkModels = orignal.linkRegisterModels
            var originalEntryIds = Set(orignal.entries.map { $0.id })
            if orignal.replace(with: model) {
                let linkModels = orignal.linkRegisterModels
                if originalLinkModels != linkModels {
                    linkRegisterControllable.deregister(links: originalLinkModels)
                    linkRegisterControllable.register(links: linkModels)
                }
                originalEntryIds.subtract(orignal.entries.map { $0.id })
                for entryId in originalEntryIds {
                    resetUsedLink(for: ItemRowModel(itemId: orignal.id, entryId: entryId, typeId: config.module))
                }
                resortItem(changed: orignal)
            }
            if updateHidden {
                itemDataModel.increaseHiddenCounter()
            }
        } else {
            setModel(with: model)
            insertIntoItems(model: model)
        }
        itemDataModel.updateTags(with: model.tags)
    }

    func updates(_ models: [ModelType]) async {
        let sortedModels = models.compactMap { $0 as? Model }.sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
        let deletedIds = await itemDataModel.items.filter { id in !sortedModels.contains { $0.id == id } }
        for id in deletedIds {
            await delete(itemId: id)
        }
        var updatedItems: [UUID] = []
        for item in sortedModels {
            await setModel(with: item)
            await itemDataModel.updateTags(with: item.tags)
            await didUpdate(model: item)
            updatedItems.append(item.id)
        }
        await itemDataModel.resetItems(updatedItems)
    }
    
    @MainActor
    func addNew(type: Int?) async -> ItemRowModel {
        var model = Model.empty
        if let type, let category = ItemListCategory(rawValue: type) {
            model.category = category
        }
        let updatedModel = model
        try? await dataControllable?.replace(id: updatedModel.id, with: updatedModel)
        insertIntoItems(model: model)
        setModel(with: model)
        return ItemRowModel(itemId: model.id, typeId: config.module)
    }

    func duplicate(model: ItemRowModel) async {
        guard let item = await self.item(for: model.itemId) else { return }
        var duplicate = item.duplicate()
        duplicate.fileUrl = try? await fileUrlDataController?.duplicate(fileUrl: item.fileUrl, for: duplicate.id)
        await replace(model: duplicate, isInsert: true, shouldRepairLinks: true)
    }

    @MainActor
    func insertIntoItems(model: Model) {
        var foundIndex: Int?
        for (index, itemId) in itemDataModel.items.enumerated() {
            if itemSync(for: itemId)?.name.localizedCompare(model.name) == .orderedDescending {
                foundIndex = index
                break
            }
        }
        itemDataModel.insert(itemId: model.id, at: foundIndex)
    }

    @MainActor func collections(isFolder: Bool, in parentId: UUID?) -> [Model] {
        return itemDataModel.items.compactMap { itemId -> Model? in
            guard let item = itemSync(for: itemId),
                  item.displayState == 0 && item.parentId == parentId && (item.category == (isFolder ? .folder : collectionCategory)) else { return nil }
            return item
        }
    }
    
    func delete(itemId: UUID) async {
        await delete(model: ItemRowModel(itemId: itemId, typeId: config.module))
    }

    func delete(model: ItemRowModel) async {
        guard let item = await self.item(for: model.itemId) else { return }
        let entries = item.entries
        try? await dataControllable?.delete(id: item.id)

        await didDelete(model: item)
        await itemDataModel.resetModel(id: item.id)

        await repairLinks(for: [model])
        await resetUsedLink(for: model)
        for entry in entries {
            await resetUsedLink(for: ItemRowModel(itemId: item.id, entryId: entry.id, typeId: config.module))
        }
    }

    func didDelete(model: ModelType) async {}
    func didUpdate(model: ModelType) async {}
    
    func name(model: ItemRowModel) async -> String {
        guard let item = await self.item(for: model.itemId) else { return "" }
        return item.name
    }

    @MainActor
    func nameSync(model: ItemRowModel) -> String {
        guard let item = self.itemSync(for: model.itemId) else { return "" }
        return item.name
    }

    func name(itemId: UUID) async -> String {
        guard let item = await self.item(for: itemId) else { return "" }
        return item.name
    }

    @MainActor
    func nameSync(itemId: UUID) -> String {
        guard let item = self.itemSync(for: itemId) else { return "" }
        return item.name
    }

    @MainActor
    func start(model: ItemRowModel, with prefix: String) -> Bool {
        nameSync(model: model).starts(with: prefix)
    }

    func toggleGroupHidden(on itemId: UUID) async {
        guard var model = await copy(of: itemId) else { return }
        model.displayState = DisplayStateMask.groupHidden.toggle(on: model.displayState)
        await replace(model: model, isInsert: false, shouldRepairLinks: true)
    }

    func resetData() async {
        for id in await itemDataModel.items {
            await delete(model: ItemRowModel(itemId: id, typeId: config.module))
        }
    }

    func save() async {
        try? await dataControllable?.save()
    }
}

// MARK - LinkRegister

public extension ItemControllable {
    @MainActor
    func repairLinks(for models: [ItemRowModel]) {
        linkRegisterControllable.repairLinks(for: models)
    }
    
    @MainActor
    func resetUsedLink(for model: ItemRowModel) {
        linkRegisterControllable.resetUsedLink(for: model)
    }
    
    @MainActor
    func usedLinks(for model: ItemRowModel) -> [EffectedItemModel] {
        linkRegisterControllable.used(for: model)
     }
}
