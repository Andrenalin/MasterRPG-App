// @copyright André Trettin

import CoreRPG
import DiceRPG
import Foundation
import Observation
import TableRPG

@MainActor @Observable
final class GeneratorDataModel: Sendable {
    init(rootItemId: UUID) {
        self.rootItemId = rootItemId
    }
    
    var itemDataModel = ItemDataModel(categoryTags: [], networkModule: .value)
    var items: [UUID] {
        get { itemDataModel.items }
        set { itemDataModel.items = newValue }
    }
    var itemData: [UUID: ModelType] {
        get { itemDataModel.itemData }
        set { itemDataModel.itemData = newValue }
    }
    
    var rootItemId: UUID
    var saveId: UUID?

    var selectedEntries: [ItemRowModel] = []
    var valueReplacement: [UUID: UUID] = [:]
    var tableValueLinks: [UUID: [ItemRowModel]] = [:]
    var childParentLinks: [ItemRowModel: ItemRowModel] = [:]
    var tableGenerators: [ItemRowModel: GeneratorControllable] = [:]

    func reset() {
        selectedEntries = []
        valueReplacement = [:]
        tableValueLinks = [:]
        childParentLinks = [:]
        tableGenerators = [:]
        items = [rootItemId]
        if let item = itemData[rootItemId] {
            itemData = [rootItemId: item]
        } else {
            itemData = [:]
        }
    }
}


struct GeneratorController {
    weak var root: CharacterRootModel!
    
    let itemController: ItemController
    let listController: ListController
    let genDataModel: GeneratorDataModel
    
    @MainActor
    init(root: CharacterRootModel, rootItemId: UUID, saveId: UUID?) {
        self.root = root
        let genDataModel = GeneratorDataModel(rootItemId: rootItemId)
        genDataModel.saveId = saveId
        let itemController = ItemController(tableRoot: root.tableRoot, dataController: nil, linkRegisterControllable: root.linkRegisterControllable) {
            guard let controller = genDataModel.tableGenerators[$0] else {
                return genDataModel.tableGenerators.reduce([ItemRowModel]()) {
                    $0 + $1.value.children(for: $1.key)
                }
            }
            return controller.children(for: $0)
        }
        genDataModel.itemDataModel = itemController.itemDataModel
        
        self.itemController = itemController
        self.listController = ListController(itemController: itemController, editController: root.editController, listStoreName: "Character Generator", hasChildren: true, searchToken: .all, categoryTags: [], selectedItems: [])
        self.genDataModel = genDataModel

        _ = addValue(with: rootItemId, after: nil)

        let dataModel = genDataModel
        listController.setSelection(onlyItems: false, onlyEntries: true, filter: .all, isHidden: false, focus: nil, mode:
            SelectionMode(selected: {
                dataModel.selectedEntries
            }, toggle: { [self] model, old in
                self.addSelectItem(itemModel: model, old: old)
            })
        )
        
        let model = ItemRowModel(itemId: rootItemId, typeId: root.itemController.itemDataModel.networkModule)
        listController.setFocusItem(model: model)
    }

    @MainActor
    func tableGeneratorControllable(for item: ItemRowModel) -> GeneratorControllable? {
        genDataModel.tableGenerators[item]
    }
    
    @MainActor
    func reset() {
        genDataModel.selectedEntries.reversed().forEach {
            _ = changeSelectItem(itemModel: $0, old: false)
        }
        listController.setSelectedItems(models: [])
        genDataModel.reset()
    }

    @MainActor 
    func roleResults() -> [ItemRowModel] {
        if !genDataModel.items.isEmpty {
            roleResult(for: ItemRowModel(itemId: genDataModel.items[0], typeId: .value))
        }

        listController.setSelectedItems(models: genDataModel.selectedEntries)
        return genDataModel.selectedEntries
    }
    
    @MainActor
    func selectedItems() -> [ItemRowModel] {
        genDataModel.selectedEntries
    }
    
    @MainActor
    func addSelectItem(itemModel: ItemRowModel, old: Bool) {
        _ = changeSelectItem(itemModel: itemModel, old: old)
    }
}

private extension GeneratorController {
    @MainActor 
    func roleResult(for item: ItemRowModel) {
        let entryIds = generateResults(for: item)
        entryIds.forEach {
            let newSelection = ItemRowModel(itemId: item.itemId, entryId: $0, typeId: .value)
            applyResults(for: newSelection)
        }
    }
    
    @MainActor
    func applyResults(for newSelection: ItemRowModel) {
        var newTables: [ItemRowModel] = []
        if let selected = genDataModel.selectedEntries.first(where: { $0 == newSelection }) {
            if let entryId = selected.entryId {
                newTables = genDataModel.tableValueLinks[entryId, default: []]
            }
        } else {
            newTables = changeSelectItem(itemModel: newSelection, old: false)
        }
        newTables.forEach {
            if $0.typeId == .value {
                roleResult(for: $0)
            } else {
                let controller = genDataModel.tableGenerators[$0]
                if let newSelections = controller?.roleTableResult(for: $0) {
                    newSelections.forEach { applyResults(for: $0) }
                }
            }
        }
    }
    
    @MainActor
    func changeSelectItem(itemModel: ItemRowModel, old: Bool) -> [ItemRowModel] {
#if os(macOS)
        guard !old else { return [] }
#else
        guard !old && itemModel.entryId != nil else { return [] }
#endif
        //print("GenC: \(itemModel.itemId) \(itemModel.entryId)\n")
        guard itemModel.typeId != .table else {
            guard let controller = genDataModel.tableGenerators[ItemRowModel(itemId: itemModel.itemId, typeId: itemModel.typeId)] else { return [] }
            let before = controller.selectedEntries
            let result = controller.changeItem(itemModel: itemModel, old: old)
            let after = controller.selectedEntries
            genDataModel.selectedEntries.removeAll(where: { before.contains($0) })

            if let parentItem = genDataModel.childParentLinks[ItemRowModel(itemId: itemModel.itemId, typeId: itemModel.typeId)], let index = genDataModel.selectedEntries.firstIndex(where: { $0 == parentItem }) {
                genDataModel.selectedEntries.insert(contentsOf: after, at: index + 1)
            } else {
                genDataModel.selectedEntries.append(contentsOf: after)
            }
            return result
        }
        
        let index: Int?
        var resetItemModel: ItemRowModel? = nil
        if itemModel.entryId == nil {
            index = genDataModel.selectedEntries.firstIndex(where: { $0.itemId == itemModel.itemId })
            // should be found
            guard index != nil else { return [] }
            resetItemModel = genDataModel.selectedEntries[index.unsafelyUnwrapped]
        } else {
            index = genDataModel.selectedEntries.firstIndex(where: { $0.itemId == itemModel.itemId && $0.entryId == itemModel.entryId })
        }
        if let index {
            // found --> remove
            let item = genDataModel.itemData[itemModel.itemId] as? ValueModel
            let sourceId = genDataModel.valueReplacement[itemModel.itemId, default: itemModel.itemId]
            item?.entries = root.itemController.itemOrEmpty(for: sourceId).entries

            let removedSelection = [itemModel]

            removedSelection.reversed().forEach { itemModel in
                removeTable(for: itemModel)
            }
            genDataModel.selectedEntries.remove(at: index)

            if itemModel.entryId == nil {
                listController.toggleExpanded(model: resetItemModel.unsafelyUnwrapped, to: false)
            } else {
                listController.toggleExpanded(model: itemModel, to: false)
            }
            if let item {
                listController.update(model: ItemRowModel(itemId: item.id, typeId: itemModel.typeId))
            }
            return []
        } else {
            if let newIndex = findIndex(itemModel: itemModel, firstIndex: 0) {
                genDataModel.selectedEntries.insert(itemModel, at: newIndex)
            } else {
                genDataModel.selectedEntries.append(itemModel)
            }

            guard let entryId = itemModel.entryId, let model =
                    genDataModel.itemData[itemModel.itemId] as? ValueModel else { return [] }
            return nextTables(for: itemModel.itemId, entry: model[entryId])
        }
    }
    
    @MainActor
    func findIndex(itemModel: ItemRowModel, firstIndex: Int) -> Int? {
        guard firstIndex < genDataModel.selectedEntries.count else { return nil }

        var newIndex = firstIndex
        var parentItem = ItemRowModel(itemId: genDataModel.rootItemId, typeId: .value)
        if let childParentItem = genDataModel.childParentLinks[ItemRowModel(itemId: itemModel.itemId, typeId: itemModel.typeId)] {
            let founded = genDataModel.selectedEntries.enumerated().first { index, element in
                guard index >= firstIndex else { return false }
                return element == childParentItem
            }
            if let founded {
                newIndex = founded.offset + 1
            } else {
                return nil
            }
            parentItem = childParentItem
        }

        let valueLinks = genDataModel.tableValueLinks[parentItem.entryId ?? UUID(), default: []]
        let count = genDataModel.selectedEntries.count
        for link in valueLinks {
            for entryIndex in newIndex...count {
                if link.itemId == itemModel.itemId {
                    // found it
                    break
                }
                if entryIndex >= count {
                    // end
                    break
                }
                if link.itemId == genDataModel.selectedEntries[entryIndex].itemId {
                    // found previous
                    newIndex = entryIndex + 1
                } else {
                    // should check next one
                }
            }
        }

        guard let entryId = itemModel.entryId, itemModel.typeId == .value else { return newIndex }

        let entries = root.itemController.itemOrEmpty(for: itemModel.itemId).entries
        
        for entry in entries {
            if newIndex >= count {
                // end
                break
            }
        
            if entry.id == entryId {
                return newIndex
            }
            if entry.id == genDataModel.selectedEntries[newIndex].entryId {
                // found previous
                newIndex += 1
                if newIndex < count {
                    newIndex = endIndex(from: newIndex, entryId: entry.id)
                }
            } else {
                for entryIndex in newIndex...(count - 1) {
                    if entry.id == genDataModel.selectedEntries[entryIndex].entryId {
                        newIndex = entryIndex + 1
                        break
                    }
                }
            }
        }
        return newIndex
    }

    @MainActor
    func endIndex(from index: Int, entryId: UUID) -> Int {
        guard let tableLinks = genDataModel.tableValueLinks[entryId], !tableLinks.isEmpty else { return index }

        guard let lastSelected = genDataModel.selectedEntries.enumerated().reversed().first(where: { selected in
            selected.offset >= index && tableLinks.contains { selected.element.itemId == $0.itemId }
        }) else { return index }

        var nextIndex = lastSelected.offset + 1
        while nextIndex < genDataModel.selectedEntries.count && genDataModel.selectedEntries[nextIndex].typeId == .table {
            nextIndex += 1
        }
        if nextIndex < genDataModel.selectedEntries.count, let lastEntryId = lastSelected.element.entryId {
            return endIndex(from: nextIndex, entryId: lastEntryId)
        }
        return nextIndex
    }

    @MainActor
    func nextTables(for tableId: UUID, entry: ValueEntryModel?) -> [ItemRowModel] {
        guard let entry else { return [] }
        let currentItem = ItemRowModel(itemId: tableId, entryId: entry.id, typeId: .value)
        let diceLinks = entry.links(for: entry.name)
            .compactMap { $0.module == .dice ? $0.itemId : nil }
        let result = max(1, diceLinks.reduce(0) { $0 + root.diceRoot.role(diceId: $1) })

        var links = entry.links(for: entry.name)
            .compactMap { $0.module == .table && $0.entryId == nil ? ItemRowModel(itemId: $0.itemId, typeId: $0.module) : nil }
        links = links.flatMap { Array(repeating: $0, count: result) }

        links.append(contentsOf: entry.links(for: entry.value)
            .compactMap { $0.module == .table && $0.entryId == nil ? ItemRowModel(itemId: $0.itemId, typeId: $0.module) : nil })
        links = links.map {
            addTable(with: $0, after: currentItem)
        }
        if let valueId = entry.valueId {
            links.append(addValue(with: valueId, after: tableId))
        }
        genDataModel.tableValueLinks[entry.id] = links
        links.forEach {
            genDataModel.childParentLinks[$0] = ItemRowModel(itemId: tableId, entryId: entry.id, typeId: .value)
        }
        if links.count > 0 {
            listController.addSubTables(child: ItemRowModel(itemId: tableId, typeId: .value), entryId: entry.id, nextItems: links)
        }
        return links
    }
    
    @MainActor
    func addTable(with item: ItemRowModel, after parent: ItemRowModel) -> ItemRowModel {
        let tableGenController = root.tableRoot.generatorControllable(for: item, parentItem: parent, listControllable: listController)
        let replacedItem = ItemRowModel(itemId: tableGenController.replacementId, typeId: .table)
        genDataModel.tableGenerators[replacedItem] = tableGenController
        return replacedItem
    }
    
    @MainActor
    func addValue(with itemId: UUID, after parent: UUID?) -> ItemRowModel {
        guard let value = root.itemController.itemSync(for: itemId)?.copy() else { return ItemRowModel(itemId: itemId, typeId: .value) }
        if genDataModel.items.contains(where: { $0 == itemId }) {
            let newValueId = UUID()
            genDataModel.valueReplacement[newValueId] = value.id
            value.id = newValueId
        }
        if let parent, let index = genDataModel.items.firstIndex(where: { $0 == parent }), index + 1 < genDataModel.items.count {
            genDataModel.items.insert(value.id, at: index + 1)
        } else {
            genDataModel.items.append(value.id)
        }
        genDataModel.itemData[value.id] = value
        return ItemRowModel(itemId: value.id, typeId: .value)
    }
    
    @MainActor
    func removeTable(for model: ItemRowModel) {
        guard let entryId = model.entryId, let links = genDataModel.tableValueLinks[entryId] else { return }
        links.forEach { linkId in
            let children = genDataModel.selectedEntries.filter { $0.itemId == linkId.itemId }
            children.forEach { _ = changeSelectItem(itemModel: $0, old: false) }
            listController.removeSubTables(from: model)
            if linkId.typeId == .table {
                guard let tableController = genDataModel.tableGenerators[model] else { return }
                tableController.removeItem(for: model)
                genDataModel.tableGenerators[model] = nil
            } else {
                genDataModel.items.removeAll(where: { $0 == linkId.itemId })
                genDataModel.itemData[linkId.itemId] = nil
                genDataModel.valueReplacement[linkId.itemId] = nil
            }
            genDataModel.childParentLinks[linkId] = nil
        }
        genDataModel.tableValueLinks[entryId] = nil
    }
}

// MARK: - Dice

extension GeneratorController {
    @MainActor
    func generateResults(for item: ItemRowModel) -> [UUID] {
        guard let item = genDataModel.itemData[item.itemId] as? ValueModel else { return [] }
        return item.entries.map { $0.id }
    }
}

// MARK: Create Value
extension GeneratorController {
    @MainActor
    func createValue(name: String) async {
        let templateItem = itemController.itemOrEmpty(for: genDataModel.rootItemId)
        var currentModel: ValueModel = await createValueModel(from: templateItem, name: name)
        var currentId = genDataModel.selectedEntries.first?.itemId ?? UUID()
        var parentEntry: ValueEntryModel? = nil
        var previousEntryId: UUID? = nil

        var modelIds: [UUID: UUID] = [currentId: currentModel.id]
        var generateIds: [UUID: UUID] = [currentModel.id: currentId]
        var firstValue: String? = nil

        for selectEntry in genDataModel.selectedEntries {
            if currentId != selectEntry.itemId && selectEntry.typeId == .value {
                await saveGeneratedModel(model: currentModel)

                if let parentId = genDataModel.childParentLinks[ItemRowModel(itemId: selectEntry.itemId, typeId: .value)]?.itemId, let previousId = modelIds[parentId]  {
                    let previousModel = loadGeneratedModel(modelId: previousId)

                    let templateModel = itemController.itemOrEmpty(for: selectEntry.itemId)
                    let lastEntry = previousModel.entries.last
                    let name = lastEntry?.name ?? ""
                    
                    if let existingId = modelIds[selectEntry.itemId] {
                        currentModel = root.itemController.itemOrEmpty(for: existingId)
                    } else {
                        currentModel = await createValueModel(from: templateModel, name: name)
                    }

                    if var lastEntry {
                        lastEntry.valueId = currentModel.id
                        previousModel.entries[previousModel.entries.count - 1] = lastEntry
                        await saveGeneratedModel(model: previousModel)
                    }
                } else {
                    let existingModelId = modelIds[selectEntry.itemId, default: UUID()]
                    currentModel = loadGeneratedModel(modelId: existingModelId)
                }
                currentId = selectEntry.itemId
                modelIds[currentId] = currentModel.id
                generateIds[currentModel.id] = currentId
                firstValue = nil
            }
            var copyEntryAndName = false
            let copyParentEntry = parentEntry?.duplicate()
            let searchId = selectEntry.itemId
            if let parentEntry,
               let parentItem = genDataModel.childParentLinks[ItemRowModel(itemId: selectEntry.itemId, typeId: selectEntry.typeId)],
                let entryId = parentItem.entryId,
               let originalId = genDataModel.tableGenerators[ItemRowModel(itemId: searchId, typeId: .table)]?.originalId,
               let tableLinks = genDataModel.tableValueLinks[entryId]?.filter({ $0.typeId == .table && ($0.itemId == searchId || $0.itemId == originalId) }),
               !tableLinks.isEmpty {
                if parentEntry.links(for: parentEntry.name).contains(where: { $0.itemId == originalId && $0.module == .table && $0.entryId == nil }) {
                    copyEntryAndName = true
                }
            }

            parentEntry = generateEntryModel(selectedItem: selectEntry, parentEntry: parentEntry, setAsName: copyEntryAndName, firstValue: firstValue)
            if previousEntryId != parentEntry?.id {
                firstValue = nil
                previousEntryId = parentEntry?.id
            }
            if firstValue == nil {
                firstValue = parentEntry?.value
            }
            if let parentEntry {
                if let index = currentModel.entries.firstIndex(where: { $0.id == parentEntry.id }) {
                    currentModel.entries[index] = parentEntry
                } else {
                    currentModel.entries.append(parentEntry)
                }
            }
            if copyEntryAndName {
                parentEntry = copyParentEntry
            }
        }
        await saveGeneratedModel(model: currentModel)

        for modelId in generateIds.keys {
            let model = loadGeneratedModel(modelId: modelId)
            let entries = model.entries.map { entry in
                let links = entry.links(for: entry.value).filter { $0.module == .value }
                var replacedEntry = entry
                links.forEach { link in
                    let replaceUrl: String
                    let replaceModel: ValueModel
                    if let linkModelId = modelIds[link.itemId] {
                        replaceModel = root.itemController.itemOrEmpty(for: linkModelId)
                    } else {
                        replaceModel = findReplacementModel(from: modelId, link: link) ?? model
                    }
                    if let entryId = link.entryId {
                        if let replaceEntryId = replaceModel.entries.first(where: { $0.name.withoutLink() == link.name })?.id {
                            replaceUrl = replaceModel.url(linkNumber: link.linkNumber, entryId: replaceEntryId)
                        } else if let generatedId = generateIds[replaceModel.id], let index = root.itemController.itemOrEmpty(for: generatedId).entries.firstIndex(where: { $0.name.contains(link.name) }), index < replaceModel.entries.count {
                            replaceUrl = replaceModel.url(linkNumber: link.linkNumber, entryId: replaceModel.entries[index].id)
                        } else {
                            replaceUrl = replaceModel.url(linkNumber: link.linkNumber, entryId: entryId)
                        }
                    } else {
                        replaceUrl = replaceModel.url(linkNumber: link.linkNumber)
                    }
                    replacedEntry.value = replacedEntry.value.replacingOccurrences(of: link.markDown, with: replaceUrl)
                }
                replacedEntry.isGenerator = false
                return replacedEntry
            }
            model.entries = entries
            await saveGeneratedModel(model: model)
        }
    }

    @MainActor private func findReplacementModel(from modelId: UUID, link: LinkReplaceModel) -> ValueModel? {
        var lastId = modelId
        while let parentId = root.itemController.itemOrEmpty(for: lastId).parentId {
            lastId = parentId
        }
        guard lastId != modelId else { return nil }
        return findReplacementModelInside(from: lastId, excludeId: modelId, link: link)
    }

    @MainActor private func findReplacementModelInside(from modelId: UUID, excludeId: UUID, link: LinkReplaceModel) -> ValueModel? {
        let model = loadGeneratedModel(modelId: modelId)

        for entry in model.entries {
            if entry.name.withoutLink() == link.name {
                return model
            }
            if let valueId = entry.valueId, valueId != excludeId {
                if let foundedModel = findReplacementModelInside(from: valueId, excludeId: excludeId, link: link) {
                    return foundedModel
                }
            }
        }
        return nil
    }

    private func createValueModel(from templateModel: ValueModel, name: String) async -> ValueModel {
        if let saveId = await genDataModel.saveId, await templateModel.id == genDataModel.rootItemId {
            return await loadGeneratedModel(modelId: saveId)
        }
        let itemRowModel = await root.itemController.addNew(type: nil)
        let item = await itemController.itemOrEmpty(for: itemRowModel.itemId).copy()
        item.name = name
        item.category = templateModel.category
        item.tags = templateModel.tags
        item.description = templateModel.description
        item.photos = templateModel.photos
        item.photoId = templateModel.photoId
        item.isGroupHiddenToggle = templateModel.isGroupHiddenToggle
        return item
    }
    
    @MainActor private func generateEntryModel(selectedItem: ItemRowModel, parentEntry: ValueEntryModel?, setAsName: Bool, firstValue: String?) -> ValueEntryModel? {
        if selectedItem.typeId == .table {
            guard var entry = parentEntry else { return nil }
            let controller = genDataModel.tableGenerators[ItemRowModel(itemId: selectedItem.itemId, typeId: .table)]
            let value = controller?.createValue(for: selectedItem, shouldUseContent: entry.isGenerator && !setAsName)
            if setAsName {
                entry.name = value ?? ""
            } else {
                if firstValue == entry.value {
                    let links = entry.links(for: entry.value).filter { $0.module == .table }
                    if !links.isEmpty {
                        links.forEach {
                            entry.value = entry.value.replacingOccurrences(of: $0.markDown, with: value ?? "")
                        }
                        return entry
                    }
                }

                if !entry.value.isEmpty {
                    entry.value.append(", ")
                }
                entry.value.append(value ?? "")
            }
            return entry
        } else {
            let model = itemController.itemOrEmpty(for: selectedItem.itemId)
            if let entryId = selectedItem.entryId {
                let entry = model[entryId]
                let links = entry.links(for: entry.value)
                let hasTableLinks = links.contains { $0.module == .table }
                let hasValueLinks = links.contains { $0.module == .value }
                return ValueEntryModel(id: UUID(), name: entry.name, type: entry.type, isGenerator: entry.isGenerator, value: hasTableLinks && !hasValueLinks ? "" : entry.value, diceId: entry.diceId)
            }
            return parentEntry
        }
    }

    @MainActor func loadGeneratedModel(modelId: UUID) -> ValueModel {
        if root.editController.model.id == modelId {
            return root.editController.model
        }
        return root.itemController.itemOrEmpty(for: modelId).copy()
    }

    @MainActor
    func saveGeneratedModel(model: ValueModel) async {
        if model.id == root.editController.model.id {
            root.editController.save(with: String(localized: "Generator change").localizedString)
        } else {
            root.itemController.replace(model: model, isInsert: false, shouldRepairLinks: false)
        }
    }
}

extension GeneratorController {
    @MainActor
    var name: String {
        root.itemController.itemOrEmpty(for: genDataModel.rootItemId).name
    }

    @MainActor
    var value: String {
        guard !genDataModel.selectedEntries.isEmpty else { return String(localized: "No item").localizedString }

        let values = genDataModel.selectedEntries.compactMap { model -> String? in
            guard let entryId = model.entryId else { return nil }
            return itemController.itemOrEmpty(for: model.itemId)[entryId].value
        }
        return values.joined(separator: "\n")
    }
}
