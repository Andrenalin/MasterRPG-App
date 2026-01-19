//
//  OldEditController-Func.swift
//  MasterRPG
//
//  Created by Andre Trettin on 19/1/2569 BE.
//

import CoreRPG
import SwiftUI


// MARK: - Quick Row Edit

extension EditController {
    @MainActor func addEntry(itemId: UUID, after entryId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        let newEntry = ValueEntryModel.empty(UUID())
        let index = (editModel.entries.firstIndex(where: { $0.id == entryId }) ?? 0) + 1
        add(entry: newEntry, into: itemId, index: index)
    }

    @MainActor func remove(itemId: UUID, entryId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        remove(entryId: entryId, from: item)
        save(updated: item, message: String(localized: "Remove entry").localizedString)
    }

    // deep delete after didDelete
    @MainActor func remove(entryId: UUID, from item: ValueModel, isDeepRemove: Bool = false) {
        guard let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return }
        let entry = item.entries[index]
        item.entries.remove(at: index)
        if let valueId = entry.valueId {
            if isDeepRemove == true {
                let subValue = itemController.itemOrEmpty(for: valueId)
                guard subValue.isGroupHidden else { return }
                delete(itemId: valueId)
            } else {
                removeChild(childId: valueId)
            }
        }
    }

    @MainActor
    func toggleSelected(itemId: UUID, entryId: UUID) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel[entryId].toggleSelection()
        if editModel[entryId].valueSelected {
            for entry in editModel.entries {
                guard entry.id != entryId && entry.type == .selection && entry.valueSelected else { continue }
                editModel[entry.id].toggleSelection()
            }
        }
        save(updated: editModel, message: String(localized: "Changed selection").localizedString)
    }

    @MainActor
    func toggleType(itemId: UUID, entryId: UUID, updatedValue: ValueEntryModel.ValueType) {
        guard let editModel = editModel(for: itemId) else { return }
        editModel[entryId].type = updatedValue
        save(updated: editModel, message: String(localized: "Change type").localizedString)
    }

    @MainActor
    func updateDecimal(itemId: UUID, entryId: UUID, value: Double) {
        guard let editModel = editModel(for: itemId) else { return }
        if editModel[entryId].valueDecimal != value {
            editModel[entryId].valueDecimal = value
            save(updated: editModel, message: String(localized: "Update decimal").localizedString)
        }
    }

    @MainActor
    func updateNumber(itemId: UUID, entryId: UUID, value: Int) {
        guard let editModel = editModel(for: itemId) else { return }
        if editModel[entryId].valueNumber != value {
            editModel[entryId].valueNumber = value
            save(updated: editModel, message: String(localized: "Update number").localizedString)
        }
    }

    @MainActor
    func updateValue(itemId: UUID, entryId: UUID, value: String) {
        guard let editModel = editModel(for: itemId) else { return }
        if editModel[entryId].value != value {
            editModel[entryId].value = value
            save(updated: editModel, message: String(localized: "Update value").localizedString)
        }
    }
}


// MARK: - Group Edit

//extension EditController {
//    @MainActor
//    func createGroup(itemId: UUID, entryIds: [UUID]) {
//        guard let item = editModel(for: itemId) else { return }
//        guard entryIds.count > 0, item.entries.count > 0, var groupIndex = item.entries.firstIndex(where: { $0.id == entryIds[0] }) else { return }
//        let valueEntryIndice = entryIds.compactMap { entryId -> Int? in
//            item.entries.firstIndex(where: { $0.id == entryId })
//        }
//        let valueEntries = valueEntryIndice.sorted().map { item.entries[$0] }
//        valueEntryIndice.sorted(by: >).forEach { item.entries.remove(at: $0) }
//
//        groupIndex = min(max(groupIndex, 0), item.entries.count)
//
//        let newValue = ValueModel(id: UUID(), name: "\(item.name) \(String(localized: "Group").localizedString)", description: item.description, tags: item.tags, category: item.category, displayState: DisplayStateMask.groupHidden.rawValue, photoId: item.photoId, photos: item.photos, entries: valueEntries)
//        let newEntry = ValueEntryModel(id: UUID(), name: String(localized: "Group").localizedString, type: .text, value: "", diceId: nil, valueId: newValue.id)
//        newValue.parentId = item.id
//
//        item.entries.insert(newEntry, at: groupIndex)
//        itemController.replace(model: newValue, isInsert: true)
//        save(updated: item, message: String(localized: "Created group").localizedString)
//    }
//
//    @MainActor
//    func ungroup(from itemId: UUID, entryIds: [UUID]) async {
//        for entryId in entryIds {
//            await ungroup(itemId: itemId, entryId: entryId)
//        }
//    }
//
//    @MainActor
//    func toggleGroup(for rootModel: ItemRowModel, models: [ItemRowModel]) async {
//        guard let editModel = editModel(for: rootModel.itemId) else { return }
//        // root is an entry
//        if let entryId = rootModel.entryId {
//            // is grouped
//            if let groupId = editModel[entryId].valueId {
//                // ungrouping
//                await ungroup(groupId: groupId, from: entryId, into: editModel.id)
//            } else {
//                await group(itemId: editModel.id, entryId: entryId, models: models)
//            }
//        } else {
//            await group(itemId: editModel.id, entryId: nil, models: models)
//        }
//    }
//
//    @MainActor
//    func valueGroupIds(value: ValueModel) -> Set<UUID> {
//        value.entries.reduce(Set<UUID>()) { groups, nextValue in
//            var all = groups
//            if let nextId = nextValue.valueId {
//                if !all.contains(nextId) {
//                    all.insert(nextId)
//                    all.formUnion(valueGroupIds(value: itemController.itemOrEmpty(for: nextId)))
//                }
//            }
//            return all
//        }
//    }
//
//    @MainActor
//    private func ungroup(itemId: UUID, entryId: UUID) async {
//        guard let editModel = editModel(for: itemId) else { return }
//        guard let groupIndex = editModel.entries.firstIndex(where: { $0.id == entryId }), let valueId = editModel[entryId].valueId else { return }
//        let valueGroupped = itemController.itemOrEmpty(for: valueId)
//        let groupEntries = valueGroupped.entries
//        editModel.entries.remove(at: groupIndex)
//        await itemController.delete(itemId: valueId)
////        for entry in groupEntries {
////            remove(entryId: entry.id, from: valueGroupped, isDeepRemove: true)
////        }
//        groupEntries.reversed().forEach {
//            editModel.entries.insert($0, at: groupIndex)
//        }
//        save(updated: editModel, message: String(localized: "Insert group").localizedString)
//    }
//
//    @MainActor
//    private func group(itemId: UUID, entryId: UUID?, models: [ItemRowModel]) async {
//        guard let editModel = editModel(for: itemId) else { return }
//
//        var entries: [ValueEntryModel] = []
//        for model in models {
//            if let entryId = model.entryId, let valueModel = await itemController.item(for: model.itemId) {
//                let entry = valueModel[entryId]
//                entries.append(entry)
//            }
//        }
//        if let entryId {
//            entries.insert(editModel[entryId], at: 0)
//        }
//
//        let value = ValueModel(id: UUID(), name: entries.first?.name ?? String(localized: "Unnamed").localizedString, description: "", tags: editModel.tags, category: editModel.category, displayState: DisplayStateMask.groupHidden.rawValue, photoId: editModel.photoId, photos: editModel.photoId != nil ? [editModel.photoId!] : [], entries: entries)
//        itemControllable.replace(model: value, isInsert: true)
//
//        let valueEntry = ValueEntryModel(id: UUID(), name: String(localized: "Group").localizedString, type: .text, value: "", valueId: value.id)
//
//        if let entryId {
//            if let index = editModel.entries.firstIndex(where: { $0.id == entryId }) {
//                editModel.entries.insert(valueEntry, at: index)
//            }
//            for entry in entries {
//                if let index = editModel.entries.firstIndex(where: { $0.id == entry.id }) {
//                    editModel.entries.remove(at: index)
//                }
//            }
//        } else {
//            editModel.entries.append(valueEntry)
//        }
//        save(updated: editModel, message: String(localized: "Grouped").localizedString)
//    }
//
//    @MainActor
//    private func ungroup(groupId: UUID, from entryId: UUID, into itemId: UUID) async {
//        guard let editModel = editModel(for: groupId) else { return }
//        guard let item = self.editModel(for: itemId) else { return }
//        if let index = item.entries.firstIndex(where: { $0.id == entryId }) {
//            item.entries.insert(contentsOf: editModel.entries, at: index)
//        } else {
//            item.entries.append(contentsOf: editModel.entries)
//        }
//        if let index = item.entries.firstIndex(where: { $0.id == entryId }) {
//            item.entries.remove(at: index)
//        }
//        await itemController.delete(itemId: groupId)
//        for entry in editModel.entries {
//            remove(entryId: entry.id, from: editModel, isDeepRemove: true)
//        }
//        save(updated: item, message: String(localized: "Ungrouped").localizedString)
//    }
//}


// MARK: - Parent / Child Relation

extension EditController {
//    @MainActor
//    func canAddChild(childId: UUID?) -> Bool {
//        guard let childId else { return true }
//        return itemController.itemOrEmpty(for: childId).parentId == nil
//    }
//
//    @MainActor
//    func addChild(childId: UUID?, into itemId: UUID, entryId: UUID) {
//        guard canAddChild(childId: childId) else { return }
//        guard let parent = editModel(for: itemId) else { return }
//        if let existingChildId = parent[entryId].valueId {
//            // save is missing
//            itemController.itemOrEmpty(for: existingChildId).parentId = nil
//        }
//        parent[entryId].valueId = childId
//        if let childId {
//            // save is missing
//            itemController.itemOrEmpty(for: childId).parentId = itemId
//        }
//        save(updated: parent, message: String(localized: "Add child item").localizedString)
//    }

    @MainActor
    func removeChild(childId: UUID?) {
        guard let childId, let parentId = itemController.itemOrEmpty(for: childId).parentId else { return }
        let child = itemController.itemOrEmpty(for: childId).copy()
        child.parentId = nil
        itemController.replace(model: child, isInsert: false)
        guard let parent = editModel(for: parentId) else { return }
        let entries = parent.entries.map {
            var entry = $0
            if entry.valueId == childId {
                entry.valueId = nil
            }
            return entry
        }
        parent.entries = entries
        save(updated: parent, message: String(localized: "Remove child item").localizedString)
    }

//    func copyAddChild(childId: UUID, into itemId: UUID, entryId: UUID) async {
//        let copiedChildId = await duplicate(itemId: childId)
//        await addChild(childId: copiedChildId, into: itemId, entryId: entryId)
//    }
}


// MARK: - Selection

//extension EditController {
//    @MainActor private func rootCharacter(for valueId: UUID) -> UUID {
//        let allCharacters = itemController.itemDataModel.items.filter { !itemController.itemOrEmpty(for: $0).isGroupHidden && itemController.itemOrEmpty(for: $0).category == .character }.map { itemController.itemOrEmpty(for: $0) }
//        let firstOne = allCharacters.first {
//            $0.entries.first {
//                first(entry: $0, with: valueId)
//            } != nil
//        }
//        if let firstOne {
//            return firstOne.id
//        } else {
//            return valueId
//        }
//    }
//
//    @MainActor private func first(entry: ValueEntryModel, with valueId: UUID) -> Bool {
//        if let childId = entry.valueId {
//            if childId == valueId {
//                return true
//            } else {
//                return itemController.itemOrEmpty(for: childId).entries.first {
//                    first(entry: $0, with: valueId)
//                } != nil
//            }
//        }
//        return false
//
//    }
//}

