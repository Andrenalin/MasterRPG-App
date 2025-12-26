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

    @discardableResult @MainActor func copy(entryId: UUID, shouldSave: Bool) -> UUID

    // MARK: - EntryList editor

    @MainActor func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationEntryId: UUID)
    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool
        
    var linkModules: [NetworkModules] { get }
    func linkSelectionDestination(for entryId: UUID) -> any NavigationDestination
    func linkSelectionDestination(for module: NetworkModules) -> any NavigationDestination
    
    var thumbnailEntryViewType: ThumbnailEntryViewType { get }
    var additioanlEnrtryViewType: AdditionalEntryViewType { get }
    
    @MainActor func additionalRowView(for entryId: UUID) -> AnyView
    @MainActor func rowText(entry: any EntryDataAccessable) -> String
    
    @MainActor func create(name: String, content: String) -> Model.Entry
    @MainActor func merge(entries: [Model.Entry], recoverEntries: [ItemRowModel]?) async -> [ItemRowModel]
    @MainActor func remove(entryId: UUID)
    @MainActor func remove(entryId: UUID, shouldSave: Bool)
}

public extension EntryDataEditable {
    @MainActor func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationEntryId: UUID) {
        addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationEntryId: destinationEntryId)
    }

    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool { false }
    
    @MainActor func addLinkInEntry(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationEntryId: UUID, separator: String = " ") {
        guard canAddLink(module: module, entryId: entryId) else { return }
        
        var entry = model[destinationEntryId]
        var content = entry.content.trimmingCharacters(in: .whitespaces)
        
        let nextLinkNumer = LinkReplaceController.links(for: content).filter { $0.itemId == itemId && $0.entryId == entryId }.reduce(-1) { max($0, $1.linkNumber) } + 1
        
        let entryLink = entryId == nil ? "" : "/\(entryId!.uuidString)"
        let linkText = "\(content.isEmpty ? "" : separator)[\(link)](\(URL.appScheme)://\(module.token)/\(nextLinkNumer)/\(itemId.uuidString)\(entryLink))"
        content.append(linkText)
        entry.content = content
        model[destinationEntryId] = entry
        save(with: String(localized: "Add Link").localizedString)
    }
    
    var thumbnailEntryViewType: ThumbnailEntryViewType { .none }
    var additioanlEnrtryViewType: AdditionalEntryViewType { .none }

    @MainActor func additionalRowView(for entryId: UUID) -> AnyView { AnyView(EmptyView()) }
    
    @MainActor func rowText(entry: any EntryDataAccessable) -> String {
        entry.name.isEmpty ? entry.content : "\(entry.name.markDownText()): \(entry.content)"
    }


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
    
    @discardableResult @MainActor func copy(entryId: UUID, shouldSave: Bool) -> UUID {
        let duplicate = model[entryId].duplicate()
        model.entries.append(duplicate)
        if shouldSave {
            let name = String(duplicate.name.prefix(16))
            save(with: String(localized: "Copy entry \(name)").localizedString)
        }
        return duplicate.id
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
    
    @MainActor func update(entryId: UUID, name: String, content: String) {
        var changed = model[entryId].name != name.withoutLink()
        model[entryId].name <=> name.withoutLink()

        let links = linkRegisterControllable.linkRegisterModel(in: content, for: ItemRowModel(itemId: model.id, entryId: entryId, typeId: itemControllable.config.module))
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
        changed = changed || model[entryId].content != newContent
        model[entryId].content <=> newContent
        if changed {
            cacheItemListModel.reset(cacheType: .row, itemId: entryId, text: rowText(entry: model[entryId]))
        }
        save(with: String(localized: "Edit entry").localizedString)
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
}

public extension EntryDataEditable {
    @MainActor func linkTextModel(for entry: any EntryDataAccessable, linkController: LinkRootController, searchModel: SearchModel, toggler: ((UUID, NetworkModules) async -> Void)? = nil) -> LinkHighlightTextModel {
        let nameText = rowText(entry: entry)
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
        linkRegisterControllable.isUsed(link: ItemRowModel(itemId: model.id, entryId: entryId, typeId: itemControllable.config.module))
    }

    @MainActor
    func used(entryId: UUID) -> [EffectedItemModel] {
        linkRegisterControllable.used(for: ItemRowModel(itemId: model.id, entryId: entryId, typeId: itemControllable.config.module))
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

