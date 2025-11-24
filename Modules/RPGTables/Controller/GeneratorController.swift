// @copyright André Trettin

import AndrenalinKit
import DiceRPG
import Foundation
import Observation

public protocol GeneratorControllable: Sendable {
    @MainActor var selectedEntries: [ItemRowModel] { get }
    @MainActor var replacementId: UUID { get }
    @MainActor var originalId: UUID { get }

    @MainActor func addItem(with rootItemId: ItemRowModel) -> ItemRowModel
    @MainActor func removeItem(for model: ItemRowModel)
    @MainActor func children(for model: ItemRowModel) -> [ItemRowModel]
    @MainActor func changeItem(itemModel: ItemRowModel, old: Bool) -> [ItemRowModel]
    @MainActor func createValue(for item: ItemRowModel, shouldUseContent: Bool) -> String
    @MainActor func roleTableResult(for item: ItemRowModel) -> [ItemRowModel]
}

@MainActor @Observable
final class GeneratorDataModel: Sendable {
    init(itemDataModel: ItemDataModel, rootItemId: UUID) {
        self.rootItemId = rootItemId
        self.itemDataModel = itemDataModel
    }
    
    let itemDataModel: ItemDataModel
    @MainActor
    var items: [UUID] {
        get { itemDataModel.items }
        set { itemDataModel.items = newValue }
    }
    @MainActor
    var itemData: [UUID: ModelType] {
        get { itemDataModel.itemData }
        set { itemDataModel.itemData = newValue }
    }
    
    var rootItemId: UUID
    var selectedEntries: [ItemRowModel] = []
    var tableReplacement: [UUID: UUID] = [:]
    var tableLinks: [UUID: [UUID]] = [:]
    var childParentLinks: [ItemRowModel: ItemRowModel] = [:]

    var parentItem: ItemRowModel?
    var replacementId = UUID()

    @MainActor
    func reset() {
        selectedEntries = []
        tableReplacement = [:]
        tableLinks = [:]
        childParentLinks = [:]
        items = [rootItemId]
        if let item = itemData[rootItemId] {
            itemData = [rootItemId: item]
        } else {
            itemData = [:]
        }
    }

    var values: [ActivatedValue] = []
}

struct GeneratorController: Sendable {
    weak var root: TableRootModel!

    let itemController: ItemController
    let listController: ListControllable
    let genDataModel: GeneratorDataModel

    @MainActor
    init(root: TableRootModel, rootItemId: UUID, parentItem: ItemRowModel, listControllable: ListControllable) {
        self.root = root
        let itemController = ItemController(dataController: nil, linkRegisterControllable: root.linkRegisterControllable)
        self.itemController = itemController
        self.listController = listControllable
        self.genDataModel = GeneratorDataModel(itemDataModel: itemController.itemDataModel, rootItemId: rootItemId)
        genDataModel.parentItem = parentItem
        
        genDataModel.replacementId = addTable(with: rootItemId, after: nil, shouldReplace: true)
    }

    @MainActor
    init(root: TableRootModel, rootItemId: UUID) {
        self.root = root
        let itemController = ItemController(dataController: nil, linkRegisterControllable: root.linkRegisterControllable)
        self.itemController = itemController
        self.listController = ListController(itemController: itemController, listStoreName: "Table Generator", hasChildren: true, searchToken: .all, categoryTags: [], selectedItems: [])
        self.genDataModel = GeneratorDataModel(itemDataModel: itemController.itemDataModel, rootItemId: rootItemId)
        
        _ = addTable(with: rootItemId, after: nil)
        
        let dataModel = genDataModel
        listController.setSelection(onlyItems: false, onlyEntries: true, filter: .all, isHidden: false, focus: nil, mode: SelectionMode(selected: {
            dataModel.selectedEntries
        }, toggle: { [self] model, old in
            self.addSelectItem(itemModel: model, old: old)
        }))
        
        let model = ItemRowModel(itemId: rootItemId, typeId: root.itemController.itemDataModel.networkModule)
        listController.setFocusItem(model: model)
    }

    @MainActor
    func reset() {
        if let first = genDataModel.selectedEntries.first {
            _ = changeSelectItem(itemModel: first, old: false)
        }
        listController.setSelectedItems(models: [])
        genDataModel.reset()
    }

    @MainActor
    func roleResults() -> [ItemRowModel] {
        if !genDataModel.items.isEmpty {
            if let last = genDataModel.selectedEntries.last {
                roleResult(for: last.itemId)
            } else {
                roleResult(for: genDataModel.items[0])
            }
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

    @MainActor
    func updateDiceResult(action: @MainActor @escaping @Sendable () -> Void) {
        _ = withObservationTracking {
            genDataModel.items.map {
                let copyId = genDataModel.tableReplacement[$0, default: $0]
                return root.itemController.itemOrEmpty(for: copyId).diceResult
            }
        } onChange: {
            Task { @MainActor in
                genDataModel.items.forEach {
                    let copyId = genDataModel.tableReplacement[$0, default: $0]
                    itemController.itemOrEmpty(for: $0).diceResult = root.itemController.itemOrEmpty(for: copyId).diceResult
                }
                action()
            }
        }
    }
}

extension GeneratorController: GeneratorControllable {
    @MainActor
    public var selectedEntries: [ItemRowModel] {
        genDataModel.selectedEntries
    }
    
    @MainActor
    public var replacementId: UUID {
        genDataModel.replacementId
    }

    @MainActor
    public var originalId: UUID {
        genDataModel.rootItemId
    }

    @MainActor
    public func addItem(with rootItemId: ItemRowModel) -> ItemRowModel {
        ItemRowModel(itemId: addTable(with: rootItemId.itemId, after: nil), typeId: .table)
    }
    
    @MainActor
    public func removeItem(for model: ItemRowModel) {
        removeTable(for: model)
    }
    
    @MainActor
    public func children(for model: ItemRowModel) -> [ItemRowModel] {
        guard let item = genDataModel.itemData[model.itemId] as? TableModel else { return [] }
        return item.entries.map { ItemRowModel(itemId: model.itemId, entryId: $0.id, typeId: .table) }
    }
    
    @MainActor
    public func changeItem(itemModel: ItemRowModel, old: Bool) -> [ItemRowModel] {
        changeSelectItem(itemModel: itemModel, old: old).map { ItemRowModel(itemId: $0, typeId: .table) }
    }
    
    @MainActor
    public func createValue(for item: ItemRowModel, shouldUseContent: Bool) -> String {
        let model: TableModel
        if item.itemId == genDataModel.replacementId {
            model = root.itemController.itemOrEmpty(for: genDataModel.rootItemId)
        } else {
            model = itemController.itemOrEmpty(for: item.itemId)
        }
        if let entryId = item.entryId {
            if shouldUseContent {
                return model[entryId].content
            }
            return model.url(linkNumber: 0, entryId: entryId)
        } else {
            return model.url(linkNumber: 0)
        }
    }

    @MainActor
    public func roleTableResult(for item: ItemRowModel) -> [ItemRowModel] {
        let entryIds = generateResults(for: item.itemId)
        return entryIds.map {
            ItemRowModel(itemId: item.itemId, entryId: $0, typeId: .table)
        }
    }
}

private extension GeneratorController {
    @MainActor
    func roleResult(for tableId: UUID) {
        let entryIds = generateResults(for: tableId)
        entryIds.forEach {
            let newSelection = ItemRowModel(itemId: tableId, entryId: $0, typeId: .table)
            
            let newTables = changeSelectItem(itemModel: newSelection, old: false)
            newTables.forEach {
                roleResult(for: $0)
            }
        }
    }
    
    @MainActor
    func changeSelectItem(itemModel: ItemRowModel, old: Bool) -> [UUID] {
#if os(macOS)
        guard !old else { return [] }
#else
        guard !old && itemModel.entryId != nil else { return [] }
#endif
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
            let item = genDataModel.itemData[itemModel.itemId] as? TableModel
            let sourceId = genDataModel.tableReplacement[itemModel.itemId, default: itemModel.itemId]
            item?.entries = root.itemController.itemOrEmpty(for: sourceId).entries

            let removedSelection: [ItemRowModel]
            if index > 0 {
                removedSelection = [itemModel]
            } else {
                removedSelection = genDataModel.selectedEntries
            }
            removedSelection.reversed().forEach { itemModel in
                removeTable(for: itemModel)
            }
            if index > 0 {
                genDataModel.selectedEntries.remove(at: index)
            } else {
                genDataModel.selectedEntries = []
            }
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
                    genDataModel.itemData[itemModel.itemId] as? TableModel else { return [] }
            if model.tableType != .all {
                model.entries = model.entries.filter { $0.id == entryId }
                listController.update(model: ItemRowModel(itemId: itemModel.itemId, typeId: itemModel.typeId))
            }
            return nextTables(for: itemModel.itemId, entry: model[entryId])
        }
    }
    
    @MainActor
    func findIndex(itemModel: ItemRowModel, firstIndex: Int) -> Int? {
        guard firstIndex < genDataModel.selectedEntries.count, let parentItem = genDataModel.childParentLinks[ItemRowModel(itemId: itemModel.itemId, typeId: itemModel.typeId)], let (firstIndex, _) = genDataModel.selectedEntries.enumerated().first(where: { index, element in
            guard index >= firstIndex else { return false }
            return element == parentItem
        }) else {
            return nil
        }

        var newIndex = firstIndex + 1
        let tableLinks = genDataModel.tableLinks[parentItem.entryId ?? UUID(), default: []]
        let count = genDataModel.selectedEntries.count
        for link in tableLinks {
            for entryIndex in newIndex...count {
                if link == itemModel.itemId {
                    // found it
                    break
                }
                if entryIndex >= count {
                    // end
                    break
                }
                if link == genDataModel.selectedEntries[entryIndex].itemId {
                    // found previous
                    newIndex = entryIndex + 1
                } else {
                    // should check next one
                }
            }
        }

        guard let entryId = itemModel.entryId, itemModel.typeId == .table else { return newIndex }

        for entry in itemController.itemOrEmpty(for: itemModel.itemId).entries {
            if newIndex >= count {
                // end
                break
            }
            if entry.id == entryId {
                let nextIndex = newIndex + 1
                if nextIndex < count {
                    if let childIndex = findIndex(itemModel: genDataModel.selectedEntries[nextIndex], firstIndex: newIndex) {
                        newIndex = childIndex
                        if newIndex >= count {
                            return newIndex
                        }
                    } else {
                        return nextIndex
                    }
                } else {
                    return newIndex + 1
                }
            }
            if entry.id == genDataModel.selectedEntries[newIndex].entryId {
                // found previous
                newIndex += 1
            } else {
                // should check next one
            }
        }
        return newIndex
    }

    @MainActor
    func nextTables(for tableId: UUID, entry: TableEntryModel?) -> [UUID] {
        guard let entry else { return [] }
        var links = entry.links(for: entry.content)
            .compactMap {
                if $0.module == .table, $0.entryId == nil {
                    return $0.itemId
                }
                return nil
            }
        links = links.map {
            addTable(with: $0, after: tableId)
        }
        genDataModel.tableLinks[entry.id] = links
        links.forEach {
            genDataModel.childParentLinks[ItemRowModel(itemId: $0, typeId: .table)] = ItemRowModel(itemId: tableId, entryId: entry.id, typeId: .table)
        }
        if links.count > 0 {
            listController.addSubTables(child: ItemRowModel(itemId: tableId, typeId: .table), entryId: entry.id, nextItems: links.map { ItemRowModel(itemId: $0, typeId: .table) })
        }
        return links
    }
    
    @MainActor
    func addTable(with id: UUID, after parent: UUID?, shouldReplace: Bool = false) -> UUID {
        guard let table = root.itemController.itemSync(for: id)?.copy() else { return id }
        if shouldReplace || genDataModel.items.contains(where: { $0 == id }) {
            let newTableId = UUID()
            genDataModel.tableReplacement[newTableId] = table.id
            table.id = newTableId
        }
        if let parent, let index = genDataModel.items.firstIndex(where: { $0 == parent }), index + 1 < genDataModel.items.count {
            genDataModel.items.insert(table.id, at: index + 1)
        } else {
            genDataModel.items.append(table.id)
        }
        genDataModel.itemData[table.id] = table

        return table.id
    }

    @MainActor
    func removeTable(for model: ItemRowModel) {
        guard let entryId = model.entryId, let links = genDataModel.tableLinks[entryId] else { return }
        links.forEach { linkId in
            let children = genDataModel.selectedEntries.filter { $0.itemId == linkId }
            children.forEach { _ = changeItem(itemModel: $0, old: false) }
            listController.removeSubTables(from: model)
            genDataModel.items.removeAll(where: { $0 == linkId })
            genDataModel.itemData[linkId] = nil
            genDataModel.tableReplacement[linkId] = nil
            genDataModel.childParentLinks[ItemRowModel(itemId: linkId, typeId: .table)] = nil
        }
        genDataModel.tableLinks[entryId] = nil
    }
}

// MARK: - Dice

extension GeneratorController {
    @MainActor
    func generateResults(for id: UUID) -> [UUID] {
        guard let item = genDataModel.itemData[id] as? TableModel else { return [] }
        switch item.tableType {
        case .dice:
            if let diceId = item.diceId {
                let result = root.diceRoot.role(diceId: diceId)
                let entry = item.entries.first {
                    let numbers = $0.name.split(separator: "-").compactMap { Int($0) }
                    if let last = numbers.last {
                        return result <= last
                    }
                    return false
                }
                if let uuid = entry?.id {
                    return [uuid]
                }
            }
            return []
        case .list:
            guard !item.entries.isEmpty else { return [] }
            let result = root.diceRoot.role(number: item.entries.count) - 1
            if result >= 0 && result < item.entries.count {
                let entry = item.entries[result]
                return [entry.id]
            } else {
                return []
            }
        case .all:
            return item.entries.map { $0.id }
        }
    }
}

// Save

extension GeneratorController {
    @MainActor
    var tableName: String {
        root.itemController.itemOrEmpty(for: genDataModel.rootItemId).name
    }

    @MainActor
    var entryName: String {
        guard !genDataModel.selectedEntries.isEmpty, let entryId = genDataModel.selectedEntries[0].entryId else { return tableName }

        return root.itemController.itemOrEmpty(for: genDataModel.rootItemId)[entryId].name
    }

    @MainActor
    var entryValue: String {
        guard !genDataModel.selectedEntries.isEmpty else { return "No item" }

        let values = genDataModel.selectedEntries.compactMap { model -> String? in
            guard let entryId = model.entryId else { return nil }
            return itemController.itemOrEmpty(for: model.itemId)[entryId].content
        }
        return values.joined(separator: "\n")
    }

    @MainActor
    var values: [ActivatedValue] {
        guard genDataModel.values.isEmpty else { return genDataModel.values }
        let updated = genDataModel.selectedEntries.flatMap { model -> [ActivatedValue] in
            guard let entryId = model.entryId else { return [] }
            let entry = itemController.itemOrEmpty(for: model.itemId)[entryId]
            return [ActivatedValue(id: UUID(), name: entry.name, activated: true), ActivatedValue(id: UUID(), name: entry.content, activated: true)]
        }
        genDataModel.values = updated
        return updated
    }

    @MainActor
    func save(name: String, value: String, isEntryOnly: Bool, values: [ActivatedValue], valueActions: ValueActions, networkActions: NetworkActions?) {

        let valueName =  name.trimmingCharacters(in: .whitespacesAndNewlines)
        let valueValue = value.trimmingCharacters(in: .whitespacesAndNewlines)

        let result: NetworkCodableDataType
        if isEntryOnly {
            result = valueActions.createEntryResult(valueName, valueValue, ResultCategory(id: genDataModel.rootItemId, childId: nil, module: .table))

        } else {
            var activatedEntries = values.filter { $0.activated }.map { $0.name }
            if !activatedEntries.count.isMultiple(of: 2) {
                activatedEntries.append("")
            }
            let entries = stride(from: 0, to: activatedEntries.count - 1, by: 2).map {
                (activatedEntries[$0], activatedEntries[$0+1])
            }
            result = valueActions.createModelResult(valueName, valueValue, entries, ResultCategory(id: genDataModel.rootItemId, childId: nil, module: .table))
        }
        if let networkActions {
            networkActions.game(result, .valueResult)
        } else {
            Task {
                await valueActions.addResult(result, nil)
            }
        }
    }
}

struct ActivatedValue: Identifiable {
    let id: UUID
    var name: String
    var activated: Bool
}
