// @copyright André Trettin

import Foundation
import SwiftUI

public enum ThumbnailEntryViewType: Hashable, Sendable {
    case none
    case photo
}

public enum AdditionalEntryViewType: Hashable, Sendable {
    case none
    case custom
    case inline
}

public protocol EntryDataEditable: EditControllable {
    @MainActor func editEntries(for item: Model) -> [Model.Entry]

    // MARK: - EntryList editor

    @MainActor func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationItemId: UUID, destinationEntryId: UUID)
    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool

    var linkModules: [NetworkModules] { get }
    func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination

    var canAddGroups: Bool { get }
    @MainActor func addNewGroup(itemId: UUID) async -> UUID
    
    var thumbnailEntryViewType: ThumbnailEntryViewType { get }
    var additioanlEnrtryViewType: AdditionalEntryViewType { get }
    
    @MainActor func additionalRowView(for source: ItemRowModel, entry: any EntryDataAccessable, textModel: LinkHighlightTextModel?) -> AnyView
    
    @MainActor func rowText(itemId: UUID, entry: any EntryDataAccessable) -> String
    
    @MainActor func groupFolders(itemId: UUID, sourceEntryId: UUID) -> [FolderRepresentable]
    @MainActor func parentFolder(itemId: UUID) -> FolderRepresentable?
    
    // MARK: - QuickEntryEditor
    
    @MainActor func create(name: String, content: String) -> Model.Entry
    @MainActor func merge(itemId: UUID, entries: [Model.Entry], recoverEntries: [ItemRowModel]?) -> [ItemRowModel]
    @MainActor func merge(itemId: UUID, entries: [Model.Entry]) -> [Model.Entry]
    @MainActor func remove(itemId: UUID, entryId: UUID)
    func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination
    
    // MARK: - Entry Editor
    
    @MainActor func update(itemId: UUID, entryId: UUID, name: String, content: String)
    @MainActor func insertEntry(itemId: UUID, name: String, content: String, position: SheetInsertionPosition) -> UUID?
    
    // MARK: - Inline Quick Editor
    
    @MainActor func entryValue(itemId: UUID, entryId: UUID?) -> String
    @MainActor func entryValueAsDecimal(itemId: UUID, entryId: UUID?) -> Double
    @MainActor func entryValueAsNumber(itemId: UUID, entryId: UUID?) -> Int
    @MainActor func entryValueAsSelected(itemId: UUID, entryId: UUID?) -> Bool
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, decimal: Double)
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, number: Int)
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, selected: Bool)
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, value: String)
    /// Encodes an existing entry's link-free game update, when supported by
    /// the owning module.
    @MainActor func gameValueEntryUpdate(itemId: UUID, entryId: UUID?) -> NetworkCodableDataType?
}

public extension EntryDataEditable {
    @MainActor func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationItemId: UUID, destinationEntryId: UUID) {
        addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destinationItemId, destinationEntryId: destinationEntryId)
    }

    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool { false }

    var canAddGroups: Bool { false }

    @MainActor func addNewGroup(itemId: UUID) async -> UUID {
        UUID() // Default implementation does nothing, returns empty UUID
    }
    
    @MainActor func addLinkInEntry(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationItemId: UUID, destinationEntryId: UUID, separator: String = " ") {
        guard canAddLink(module: module, entryId: entryId), var item = editModel(for: destinationItemId) else { return }
        
        var entry = item[destinationEntryId]
        var content = entry.content.trimmingCharacters(in: .whitespaces)
        
        let nextLinkNumer = LinkReplaceController.links(for: content).filter { $0.itemId == itemId && $0.entryId == entryId }.reduce(-1) { max($0, $1.linkNumber) } + 1
        
        let entryLink = entryId == nil ? "" : "/\(entryId!.uuidString)"
        let linkText = "\(content.isEmpty ? "" : separator)[\(link)](\(URL.appScheme)://\(module.token)/\(nextLinkNumer)/\(itemId.uuidString)\(entryLink))"
        content.append(linkText)
        entry.content = content
        item[destinationEntryId] = entry
        save(updated: item, message: String(localized: "Add Link", bundle: .module).localizedString)
    }
    
    var thumbnailEntryViewType: ThumbnailEntryViewType { .none }
    var additioanlEnrtryViewType: AdditionalEntryViewType { .none }
    
    @MainActor func additionalRowView(for source: ItemRowModel, entry: any EntryDataAccessable, textModel: LinkHighlightTextModel?) -> AnyView { AnyView(EmptyView()) }
    
    @MainActor func rowText(itemId: UUID, entry: any EntryDataAccessable) -> String {
        entry.name.isEmpty ? entry.content : "\(entry.name.markDownText()): \(entry.content)"
    }
    
    @MainActor func editEntries(for item: Model) -> [Model.Entry] {
        item.entries
    }
    
    @MainActor func validateEntries(model: Model) {
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
    
    @MainActor func addNewEntry(itemId: UUID) -> UUID {
        let entry = Model.Entry.empty
        add(entry: entry, itemId: itemId)
        return entry.id
    }
    
    @MainActor
    func add(entry: Model.Entry, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        add(entry: entry, into: item)
    }
    
    @MainActor
    func add(entry: Model.Entry, into itemId: UUID, index: Int? = nil) {
        guard let editModel = editModel(for: itemId) else { return }
        add(entry: entry, into: editModel, index: index)
    }
    
    @MainActor
    private func add(entry: Model.Entry, into item: Model, index: Int? = nil) {
        let validatedIndex = index ?? editEntries(for: item).count
        item.entries.insert(entry, at: validatedIndex)
        save(updated: item, message: String(localized: "Add entry", bundle: .module).localizedString)
    }
    
    @MainActor func copy(itemId: UUID, entryIds: [UUID]) {
        for entryId in entryIds {
            _ = copy(itemId: itemId, entryId: entryId)
        }
    }
    
    @MainActor func copy(itemId: UUID, entryId: UUID) -> UUID? {
        guard let item = editModel(for: itemId) else { return nil }
        let duplicate = item[entryId].duplicate()
        item.entries.append(duplicate)
        let name = String(duplicate.name.prefix(16))
        save(updated: item, message: String(localized: "Copy entry \(name)", bundle: .module).localizedString)
        return duplicate.id
    }
    
    @MainActor func remove(itemId: UUID, entryIndexSet: IndexSet) {
        guard let item = editModel(for: itemId) else { return }
        let ids = entryIndexSet.map { item.entries[$0].id }
        remove(itemId: itemId, entryIds: ids)
    }
    
    @MainActor func remove(itemId: UUID, entryIds: [UUID]) {
        for entryId in entryIds {
            remove(itemId: itemId, entryId: entryId)
        }
    }
    
    @MainActor func remove(itemId: UUID, entryId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        guard let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return }
        item.entries.remove(at: index)
        save(updated: item, message: String(localized: "Remove entry", bundle: .module).localizedString)
    }
    
    @MainActor func update(itemId: UUID, entryId: UUID, name: String, content: String) {
        updateDefault(itemId: itemId, entryId: entryId, name: name, content: content, nameWithLink: false)
    }

    @MainActor
    func insertEntry(itemId: UUID, name: String, content: String, position: SheetInsertionPosition) -> UUID? {
        guard let item = editModel(for: itemId) else { return nil }

        let entry = create(name: name, content: content)
        let insertionIndex: Int
        switch position {
        case .end:
            insertionIndex = item.entries.count
        case .after(let anchorEntryID):
            insertionIndex = item.entries.firstIndex(where: { $0.id == anchorEntryID })
                .map { $0 + 1 } ?? item.entries.count
        }

        add(entry: entry, into: itemId, index: insertionIndex)
        return entry.id
    }
    
    @MainActor func updateDefault(itemId: UUID, entryId: UUID, name: String, content: String, nameWithLink: Bool) {
        guard var item = editModel(for: itemId) else { return }
        let validedName = nameWithLink ? name : name.withoutLink()
        var changed = item[entryId].name != validedName
        item[entryId].name <=> validedName
        
        let links = linkRegisterController.linkRegisterModel(in: content, for: ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemControllable.config.module))
        var seenIds: Set<UUID> = []
        var newContent = content
        for link in links {
            guard seenIds.contains(link.id) else {
                seenIds.insert(link.id)
                continue
            }
            let newLink = link.duplicate()
            guard let oldLinkText = link.markDown, let range = content.firstRange(of: oldLinkText) else { continue }
            newContent = newContent.replacingOccurrences(of: oldLinkText, with: newLink.markDown ?? oldLinkText, range: range)
            linkRegisterController.register(links: [newLink])
        }
        changed = changed || item[entryId].content != newContent
        item[entryId].content <=> newContent
        if changed {
            cacheItemListModel.reset(cacheType: .row, itemId: entryId, text: rowText(itemId: item.id, entry: item[entryId]))
        }
        save(updated: item, message: String(localized: "Edit entry", bundle: .module).localizedString)
    }

    @MainActor func move(itemId: UUID, entryIds: [UUID]) {
        guard let item = editModel(for: itemId) else { return }
        let entries = entryIds.compactMap { id in item.entries.first { $0.id == id }}
        item.entries = entries
        save(updated: item, message: String(localized: "Reorder entries", bundle: .module).localizedString)
    }

    @MainActor func move(itemId: UUID, entryId: UUID, up: Bool) {
        guard let item = editModel(for: itemId) else { return }
        guard let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return }
        if up {
            guard index > 0 else { return }
            item.entries.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        } else {
            guard index < item.entries.count - 1 else { return }
            item.entries.move(fromOffsets: IndexSet(integer: index + 1), toOffset: index)
        }
        save(updated: item, message: String(localized: up ? "Move entry up" : "Move entry down", bundle: .module).localizedString)
    }
    
    @MainActor func move(itemId: UUID, entryId: UUID, into: ItemRowModel) -> Bool {
        guard let item = editModel(for: into.itemId) else { return false }
        guard let otherItem = editModel(for: itemId), let index = otherItem.entries.firstIndex(where: { $0.id == entryId }) else { return false }
        let entry = otherItem.entries.remove(at: index)
        item.entries.append(entry)
        save(updated: otherItem, message: String(localized: "remove entry", bundle: .module).localizedString)
        save(updated: item, message: String(localized: "add entry", bundle: .module).localizedString)
        return true
    }
    
    @MainActor func groupFolders(itemId: UUID, sourceEntryId: UUID) -> [FolderRepresentable] { [] }

    @MainActor func move(itemId: UUID, sourceEntryId: UUID, into folder: FolderRepresentable) {
        guard let item = editModel(for: itemId), let group = editModel(for: folder.id) else { return }
        let entry = item[sourceEntryId]
        item.entries.removeAll(where: { $0.id == sourceEntryId })
        group.entries.append(entry)
        save(updated: item, message: String(localized: "remove entry", bundle: .module).localizedString)
        save(updated: group, message: String(localized: "move entry", bundle: .module).localizedString)
    }

    @MainActor func parentFolder(itemId: UUID) -> FolderRepresentable? { nil }

    @MainActor func moveOutOfGroup(itemId: UUID, sourceEntryId: UUID, parent: FolderRepresentable) {
        guard let group = editModel(for: itemId), let parentItem = editModel(for: parent.id) else { return }
        let entry = group[sourceEntryId]
        group.entries.removeAll(where: { $0.id == sourceEntryId })
        parentItem.entries.append(entry)
        save(updated: group, message: String(localized: "remove entry", bundle: .module).localizedString)
        save(updated: parentItem, message: String(localized: "move entry out", bundle: .module).localizedString)
    }
}

// MARK: - Inline Quick Editor

public extension EntryDataEditable {
    @MainActor func entryValue(itemId: UUID, entryId: UUID?) -> String { "" }
    @MainActor func entryValueAsDecimal(itemId: UUID, entryId: UUID?) -> Double { 0.0 }
    @MainActor func entryValueAsNumber(itemId: UUID, entryId: UUID?) -> Int { 0 }
    @MainActor func entryValueAsSelected(itemId: UUID, entryId: UUID?) -> Bool { false }
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, decimal: Double) {}
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, number: Int) {}
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, selected: Bool) {}
    @MainActor func updateValue(itemId: UUID, entryId: UUID?, value: String) {}
    @MainActor func gameValueEntryUpdate(itemId: UUID, entryId: UUID?) -> NetworkCodableDataType? { nil }
}

public extension EntryDataEditable {
    @MainActor func linkTextModel(itemId: UUID, for entry: any EntryDataAccessable, linkController: any LinkControllable, cacheItemListModel: CacheItemListModel, searchModel: SearchModel, toggler: ((UUID, NetworkModules) async -> Void)? = nil) -> LinkHighlightTextModel {
        let nameText = rowText(itemId: itemId, entry: entry)
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entry.id) else {
            let model = LinkHighlightTextModel(linkControllable: linkController, text: nameText, highlightedText: searchModel.searchText, toggler: toggler)        
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entry.id, linkModel: model)
            return model
        }
        if nameText != linkModel.text {
            linkModel.reset(text: nameText)
        }
        return linkModel
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
