// @copyright André Trettin

import Foundation
import Observation

public protocol ItemControllable: Sendable  {
    associatedtype Model: ItemDataAccessable & ItemDiffComparable & ItemDuplicatable & ItemLinkRegistable & Identifiable & Equatable & Hashable & Codable & ModelType
    
    var dataControllable: (any DataPersistenceControllable)? { get }
    
    @MainActor
    var linkRegisterControllable: LinkRegisterControllable { get }
    var itemDataModel: ItemDataModel { get }
    
    // overwrites
    @MainActor func children(for model: ItemRowModel) -> [ItemRowModel]
    @MainActor func createLink(model: ItemRowModel) -> String
    
    func didDelete(model: ModelType) async
    func didUpdate(model: ModelType) async
    func duplicate(model: ItemRowModel) async
    func fileUrl(for itemId: UUID) async -> FileUrl?
    func loadableUrl(for model: ItemRowModel) async -> URL?
    @MainActor func itemTree(from rootModel: ItemRowModel?, to childModel: ItemRowModel) -> [ItemRowModel]
    
    @MainActor func childrenTree(for model: ItemRowModel) -> ItemRowModel?
    @MainActor func filterChildren(model: ItemRowModel, search: String, isHidden: Bool, filterTags: [TagFilterSelection], deep: Int) -> ListFilterOptions
}

// MARK: - Manipulate Model

public extension ItemControllable {
    @MainActor
    func copy(of itemId: UUID) -> Model? {
        self.itemOrEmpty(for: itemId).copy()
    }

    func fileUrl(for itemId: UUID) async -> FileUrl? {
        nil
    }

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
                    repairLinks(for: originalEntryIds.map { ItemRowModel(itemId: orignal.id, entryId: $0, typeId: itemDataModel.networkModule) })
                }
                for entryId in originalEntryIds {
                    resetUsedLink(for: ItemRowModel(itemId: orignal.id, entryId: entryId, typeId: itemDataModel.networkModule))
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

    @MainActor
    func update(model: ModelType?) {
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
                    resetUsedLink(for: ItemRowModel(itemId: orignal.id, entryId: entryId, typeId: itemDataModel.networkModule))
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
        return ItemRowModel(itemId: model.id, typeId: itemDataModel.networkModule)
    }

    @MainActor
    func createLink(model: ItemRowModel) -> String {
        guard let item = self.itemSync(for: model.itemId) else { return "" }
        if let entryId = model.entryId {
            return item.url(linkNumber: 0, entryId: entryId)
        } else {
            return item.url(linkNumber: 0)
        }
    }

    func duplicate(model: ItemRowModel) async {
        guard let item = await self.item(for: model.itemId) else { return }
        let duplicate = item.duplicate()
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

    func delete(itemId: UUID) async {
        await delete(model: ItemRowModel(itemId: itemId, typeId: itemDataModel.networkModule))
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
            await resetUsedLink(for: ItemRowModel(itemId: item.id, entryId: entry.id, typeId: itemDataModel.networkModule))
        }
    }

    func childrenTree(for model: ItemRowModel) -> ItemRowModel? { nil }
    
    @MainActor
    func filter(model: ItemRowModel, search: String, isHidden: Bool, filterTags: [TagFilterSelection], enableFilterChildren: Bool = false, deep: Int = 0) -> ListFilterOptions {
        guard deep < 4 else { return .notMatch }
        guard let item = self.itemSync(for: model.itemId) else { return .match }
        
        if let entryId = model.entryId {
            guard !(isHidden && item[entryId].isGroupHidden) else { return .notMatch }
        } else {
            guard !(isHidden && item.isGroupHidden) else { return .notMatch }
        }

        guard !search.isEmpty || !filterTags.isEmpty else { return .match }

        if let entryId = model.entryId {
            if enableFilterChildren || search.count > 4 {
                let children = filterChildren(model: ItemRowModel(itemId: model.itemId, entryId: entryId, typeId: model.typeId), search: search, isHidden: false, filterTags: filterTags, deep: deep)
                if children != .notMatch {
                    return children
                }
                return item[entryId].filter(search, selectedTags: filterTags) ? .match : .notMatch
            }
            return .match
        } else {
            let result = TagFilterSelection.filter(for: item.tags + ["\(item.category.title)"], with: filterTags, exclude: "\(ItemListCategory.hide.title)")
            let parent = result && item.filter(search)
            if enableFilterChildren {
                var children = item.entries.first { $0.filter(search, selectedTags: filterTags) }
                if children == nil {
                    for entry in item.entries {
                        if filter(model: ItemRowModel(itemId: model.itemId, entryId: entry.id, typeId: model.typeId), search: search, isHidden: false, filterTags: filterTags, deep: deep + 1) != .notMatch {
                            children = entry
                            break
                        }
                    }
                }
                
                if parent && children != nil {
                    return .childrenMatch
                } else if parent {
                    return .match
                }
                return children != nil ? .onlyChildrenMatch : .notMatch
                    
            }
            return parent ? .match : .notMatch
        }
    }
    
    @MainActor func filterChildren(model: ItemRowModel, search: String, isHidden: Bool, filterTags: [TagFilterSelection], deep: Int) -> ListFilterOptions { .notMatch }

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
            await delete(model: ItemRowModel(itemId: id, typeId: itemDataModel.networkModule))
        }
    }

    func save() async {
        try? await dataControllable?.save()
    }

    func itemTree(from rootModel: ItemRowModel?, to childModel: ItemRowModel) -> [ItemRowModel] {
        []
    }

    func loadableUrl(for model: ItemRowModel) async -> URL? { nil }
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
