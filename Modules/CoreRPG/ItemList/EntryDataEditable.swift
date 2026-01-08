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
}

public protocol EntryDataEditable: EditControllable {
    func editEntries(for item: Model) -> [Model.Entry]

    // MARK: - EntryList editor

    @MainActor func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationItemId: UUID, destinationEntryId: UUID)
    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool
        
    var linkModules: [NetworkModules] { get }
    func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination
    func linkSelectionDestination(for module: NetworkModules) -> any NavigationDestination
    
    var thumbnailEntryViewType: ThumbnailEntryViewType { get }
    var additioanlEnrtryViewType: AdditionalEntryViewType { get }
    
    @MainActor func additionalRowView(for entryId: UUID) -> AnyView
    @MainActor func rowText(itemId: UUID, entry: any EntryDataAccessable) -> String
    
    // MARK: - QuickEntryEditor
    
    @MainActor func create(name: String, content: String) -> Model.Entry
    @MainActor func merge(itemId: UUID, entries: [Model.Entry], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel]
    @MainActor func remove(itemId: UUID, entryId: UUID)
}

public extension EntryDataEditable {
    @MainActor func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationItemId: UUID, destinationEntryId: UUID) {
        addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destinationItemId, destinationEntryId: destinationEntryId)
    }
    
    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool { false }
    
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
        save(updated: item, message: String(localized: "Add Link").localizedString)
    }
    
    var thumbnailEntryViewType: ThumbnailEntryViewType { .none }
    var additioanlEnrtryViewType: AdditionalEntryViewType { .none }
    
    @MainActor func additionalRowView(for entryId: UUID) -> AnyView { AnyView(EmptyView()) }
    
    @MainActor func rowText(itemId: UUID, entry: any EntryDataAccessable) -> String {
        entry.name.isEmpty ? entry.content : "\(entry.name.markDownText()): \(entry.content)"
    }
    
    func editEntries(for item: Model) -> [Model.Entry] {
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
        save(updated: item, message: String(localized: "Add entry").localizedString)
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
        save(updated: item, message: String(localized: "Copy entry \(name)").localizedString)
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
        save(updated: item, message: String(localized: "Remove entry").localizedString)
    }
    
    @MainActor func update(itemId: UUID, entryId: UUID, name: String, content: String) {
        guard var item = editModel(for: itemId) else { return }
        var changed = item[entryId].name != name.withoutLink()
        item[entryId].name <=> name.withoutLink()
        
        let links = linkRegisterControllable.linkRegisterModel(in: content, for: ItemRowModel(itemId: itemId, entryId: entryId, typeId: itemControllable.config.module))
        var seenIds: Set<UUID> = []
        var newContent = content
        for link in links {
            guard seenIds.contains(link.id) else {
                seenIds.insert(link.id)
                continue
            }
            let newLink = link.duplicate()
            // linkRegisterControllable.markDown(for: link)
            guard let oldLinkText = link.markDown, let range = content.firstRange(of: oldLinkText) else { continue }
            newContent = newContent.replacingOccurrences(of: oldLinkText, with: newLink.markDown ?? oldLinkText, range: range)
            linkRegisterControllable.register(links: [newLink])
        }
        changed = changed || item[entryId].content != newContent
        item[entryId].content <=> newContent
        if changed {
            cacheItemListModel.reset(cacheType: .row, itemId: entryId, text: rowText(itemId: item.id, entry: item[entryId]))
        }
        save(updated: item, message: String(localized: "Edit entry").localizedString)
    }
    
    @MainActor func move(itemId: UUID, entryFrom: IndexSet, to: Array<UUID>.Index) {
        guard let item = editModel(for: itemId) else { return }
        var destination = to
        if destination >= item.entries.count {
            destination = item.entries.count - 1
        }
        item.entries.move(fromOffsets: entryFrom, toOffset: destination)
        save(updated: item, message: String(localized: "Reorder entries").localizedString)
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
        let title: LocalizedStringResource = up ? "Move entry up" : "Move entry down"
        save(updated: item, message: String(localized: title).localizedString)
    }
    
    @MainActor func move(itemId: UUID, entryId: UUID, into: ItemRowModel) {
        guard let item = editModel(for: into.itemId) else { return }
        guard let otherItem = editModel(for: itemId), let index = otherItem.entries.firstIndex(where: { $0.id == entryId }) else { return }
        let entry = otherItem.entries.remove(at: index)
        item.entries.append(entry)
        save(updated: otherItem, message: String(localized: "remove entry").localizedString)
        save(updated: item, message: String(localized: "add entry").localizedString)
    }
}

public extension EntryDataEditable {
    @MainActor func linkTextModel(itemId: UUID, for entry: any EntryDataAccessable, linkController: LinkRootController, searchModel: SearchModel, toggler: ((UUID, NetworkModules) async -> Void)? = nil) -> LinkHighlightTextModel {
        let nameText = rowText(itemId: itemId, entry: entry)
        guard let linkModel = cacheItemListModel.itemLink(cacheType: .row, itemId: entry.id) else {
            let model = LinkHighlightTextModel(linkControllable: linkController.linkControllable, text: nameText, highlightedText: searchModel.searchText, toggler: toggler)        
            cacheItemListModel.setItemLink(cacheType: .row, itemId: entry.id, linkModel: model)
            return model
        }
        if nameText != linkModel.text {
            linkModel.reset(text: nameText)
        }
        return linkModel
    }
    
//    @MainActor
//    func isUsed(rowModels: [ItemRowModel]) -> Bool {
//        for rowModel in rowModels {
//            if linkRegisterControllable.isUsed(link: rowModel) {
//                return true
//            }
//        }
//        return false
//    }

//    @MainActor
//    func isUsed(entryId: UUID) -> Bool {
//        linkRegisterControllable.isUsed(link: ItemRowModel(itemId: model.id, entryId: entryId, typeId: itemControllable.config.module))
//    }
//
//    @MainActor
//    func used(entryId: UUID) -> [EffectedItemModel] {
//        linkRegisterControllable.used(for: ItemRowModel(itemId: model.id, entryId: entryId, typeId: itemControllable.config.module))
//    }
    
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

