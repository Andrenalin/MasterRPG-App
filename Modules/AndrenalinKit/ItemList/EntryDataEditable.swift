// @copyright André Trettin

import Foundation
import SwiftUI

public protocol EntryDataEditable: EditControllable {
    func editEntries(for item: Model) -> [Model.Entry]

    @MainActor func copy(entryId: UUID, shouldSave: Bool)
    @MainActor func remove(entryId: UUID)
    @MainActor func remove(entryId: UUID, shouldSave: Bool)
}

public extension EntryDataEditable {
    @MainActor
    var editEntries: [Model.Entry] {
        editEntries(for: model)
    }
    
    func editEntries(for item: Model) -> [Model.Entry] {
        item.entries
    }

    @MainActor
    func validateEntries() {
        var seenIds: Set<UUID> = []
        guard !model.entries.allSatisfy({
            let result = !seenIds.contains($0.id)
            seenIds.insert($0.id)
            return result
        }) else { return }

        var entries: [Model.Entry] = []
        seenIds = []
        model.entries.forEach { entry in
            guard !seenIds.contains(entry.id) else { return }
            seenIds.insert(entry.id)
            entries.append(entry)
        }
        model.entries = entries
    }

    @MainActor
    func addNewEntry() -> UUID {
        let entry = Model.Entry.empty
        add(entry: entry)
        editorModel.activateDetailEditMode = false
        return entry.id
    }

    @MainActor
    func add(entry: Model.Entry) {
        add(entry: entry, into: model)
    }

    @MainActor
    func add(entry: Model.Entry, into itemId: UUID, index: Int? = nil) {
        let item = model.id == itemId ? model : itemControllable.itemOrEmpty(for: itemId).copy() as? Model
        guard let item else { return }
        add(entry: entry, into: item, index: index)
    }

    @MainActor
    private func add(entry: Model.Entry, into item: Model, index: Int? = nil) {
        var item = item
        let validatedIndex = index ?? editEntries(for: item).count
        item.entries.insert(entry, at: validatedIndex)
        if  item.id == model.id {
            save(with: String(localized: "Add entry").localizedString)
        } else {
            itemControllable.replace(model: item, isInsert: false, shouldRepairLinks: true)
        }
    }
    
    @MainActor
    func copy(entryIds: [UUID]) {
        for entryId in entryIds {
            copy(entryId: entryId, shouldSave: false)
        }
        save(with: String(localized: "Copy entries").localizedString)
    }
    
    @MainActor
    func copy(entryId: UUID, shouldSave: Bool) {
        let duplicate = model[entryId].duplicate()
        model.entries.append(duplicate)
        if shouldSave {
            let name = String(duplicate.name.prefix(16))
            save(with: String(localized: "Copy entry \(name)").localizedString)
        }
    }
    
    @MainActor
    func remove(entryIndexSet: IndexSet) {
        let ids = entryIndexSet.map { model.entries[$0].id }
        remove(entryIds: ids)
    }
    
    @MainActor
    func remove(entryIds: [UUID]) {
        for entryId in entryIds {
            remove(entryId: entryId, shouldSave: false)
        }
        save(with: String(localized: "Remove entries").localizedString)
    }

    @MainActor
    func remove(entryId: UUID) {
        remove(entryId: entryId, shouldSave: true)
    }

    @MainActor
    func remove(entryId: UUID, shouldSave: Bool) {
        guard let index = model.entries.firstIndex(where: { $0.id == entryId }) else { return }
        model.entries.remove(at: index)
        if shouldSave {
            save(with: String(localized: "Remove entry").localizedString)
        }
    }
    
    @MainActor
    func move(entryFrom: IndexSet, to: Array<UUID>.Index) {
        model.entries.move(fromOffsets: entryFrom, toOffset: to)
        save(with: String(localized: "Reorder entries").localizedString)
    }
    
    @MainActor
    func move(entryId: UUID, up: Bool) {
        guard let index = model.entries.firstIndex(where: { $0.id == entryId }) else { return }
        if up {
            guard index > 0 else { return }
            model.entries.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        } else {
            guard index < model.entries.count - 1 else { return }
            model.entries.move(fromOffsets: IndexSet(integer: index + 1), toOffset: index)
        }
        let title: LocalizedStringResource = up ? "Move entry up" : "Move entry down"
        save(with: String(localized: title).localizedString)
    }
    
    @MainActor
    func isUsed(rowModels: [ItemRowModel]) -> Bool {
        for rowModel in rowModels {
            if linkRegisterControllable.isUsed(link: rowModel) {
                return true
            }
        }
        return false
    }

    @MainActor
    func isUsed(entryId: UUID) -> Bool {
        linkRegisterControllable.isUsed(link: ItemRowModel(itemId: model.id, entryId: entryId, typeId: itemControllable.itemDataModel.networkModule))
    }

    @MainActor
    func used(entryId: UUID) -> [EffectedItemModel] {
        linkRegisterControllable.used(for: ItemRowModel(itemId: model.id, entryId: entryId, typeId: itemControllable.itemDataModel.networkModule))
    }
    
    func scanReplace(entry: Model.Entry, linkEntry: LinkEntryModel, getLink: @Sendable @escaping (Model.Entry) -> String, setLink: @Sendable @escaping (String, Model.Entry) -> Model.Entry, caseInsensitive: Bool, words: Bool) -> Model.Entry {
        var replacedEntry = entry
        var nextRange = Range(uncheckedBounds: (getLink(replacedEntry).startIndex, getLink(replacedEntry).endIndex))
        while let range = getLink(replacedEntry).range(of: linkEntry.reference, options: caseInsensitive ? [.caseInsensitive] : [], range: nextRange) {
            let endIndex = getLink(replacedEntry).endIndex
            let lastIndex = range.upperBound == endIndex ? getLink(replacedEntry).index(before: endIndex) : range.upperBound
            let lastCharacter = getLink(replacedEntry)[lastIndex]
            if (!words || (lastCharacter.isWhitespace || lastCharacter.isPunctuation)) && !getLink(replacedEntry).isRangeInsideLink(range) {
                var link = getLink(replacedEntry)
                link.replaceSubrange(range, with: linkEntry.markdownUrl)
                replacedEntry = setLink(link, replacedEntry)
            }
            guard range.upperBound < getLink(replacedEntry).endIndex else { break }
            let nextIndex = getLink(replacedEntry).index(after: range.upperBound)
            nextRange = Range(uncheckedBounds: (nextIndex, getLink(replacedEntry).endIndex))
        }
        return replacedEntry
    }
}
