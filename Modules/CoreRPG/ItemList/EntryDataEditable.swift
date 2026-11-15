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

public protocol SheetEditTypeControllable: Sendable {
    var supportedSheetEditTypes: [SheetModelEditType] { get }
    @MainActor func updateSheetEditType(itemId: UUID, entryId: UUID, editType: SheetModelEditType)
}

public protocol EntryDataEditable: EditControllable {
    @MainActor func editEntries(for item: Model) -> [Model.Entry]

    // MARK: - EntryList editor

    @MainActor func add(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationItemId: UUID, destinationEntryId: UUID)
    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool

    var linkModules: [NetworkModules] { get }
    func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination

    var canAddGroups: Bool { get }
    var canConvertGroups: Bool { get }
    @MainActor func addNewGroup(itemId: UUID) async -> UUID
    @MainActor func canBecomeGroup(itemId: UUID) -> Bool
    @MainActor func convertToGroup(itemId: UUID, entryId: UUID, existingItemId: UUID?) async -> UUID
    /// Whether the item `itemId` can become a hidden group value inside `targetId`.
    @MainActor func canMoveIntoGroup(itemId: UUID, into targetId: UUID) -> Bool
    /// Moves the item `itemId` into `targetId`: a new entry of `targetId` stands for the item,
    /// which becomes a hidden group of the target. Returns the new entry's id, or `nil` if the
    /// item cannot be moved.
    @MainActor func moveIntoGroup(itemId: UUID, into targetId: UUID) -> UUID?

    var thumbnailEntryViewType: ThumbnailEntryViewType { get }
    /// Whether `entry` has an image for its thumbnail slot. An entry with nothing to show (a map
    /// room without coordinates) gets a placeholder of the same size instead, so the row layout
    /// stays the same. Defaults to `true`.
    func hasThumbnailImage(for entry: any EntryDataAccessible) -> Bool
    var additionalEntryViewType: AdditionalEntryViewType { get }
    
    @MainActor func additionalRowView(for source: ItemRowModel, entry: any EntryDataAccessible, textModel: LinkHighlightTextModel?) -> AnyView
    
    @MainActor func rowText(itemId: UUID, entry: any EntryDataAccessible) -> String
    
    @MainActor func groupFolders(itemId: UUID, sourceEntryId: UUID) -> [FolderRepresentable]
    @MainActor func parentFolder(itemId: UUID) -> FolderRepresentable?
    /// Whether `parentFolder(itemId:)`'s result is a true value-group parent
    /// this entry can move back out to, as opposed to some other resolvable
    /// parent (e.g. an item-list folder) that isn't a valid destination for an
    /// entry. Defaults to `true` (no restriction); a module whose `parentFolder`
    /// can resolve through an unrelated hierarchy overrides this to distinguish
    /// the two — see `SheetContextMenuMoveOutOfGroupButton` in `SheetContextMenuView.swift`.
    @MainActor func isValueGroupParent(itemId: UUID) -> Bool

    // MARK: - QuickEntryEditor
    
    @MainActor func create(name: String, content: String) -> Model.Entry
    /// `forceSave` is not defaulted here because protocol requirements cannot carry
    /// default argument values; use the 3-argument convenience overload in the
    /// extension below (`forceSave: false`) unless the caller needs to opt into
    /// persisting regardless of an active game (the standalone item editor does).
    @MainActor func merge(itemId: UUID, entries: [Model.Entry], recoverEntries: [ItemRowModel]?, forceSave: Bool) -> [ItemRowModel]
    @MainActor func merge(itemId: UUID, entries: [Model.Entry]) -> [Model.Entry]
    /// `forceSave` is not defaulted here because protocol requirements cannot carry
    /// default argument values; use the 2-argument convenience overload in the
    /// extension below (`forceSave: false`) unless the caller needs to opt into
    /// persisting regardless of an active game (the standalone item editor does).
    @MainActor func remove(itemId: UUID, entryId: UUID, forceSave: Bool)
    func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination

    // MARK: - Entry Editor

    /// `forceSave` is not defaulted here because protocol requirements cannot carry
    /// default argument values; use the 4-argument convenience overload in the
    /// extension below (`forceSave: false`) unless the caller needs to opt into
    /// persisting regardless of an active game (the standalone item editor does).
    @MainActor func update(itemId: UUID, entryId: UUID, name: String, content: String, forceSave: Bool)
    /// `forceSave` is not defaulted here because protocol requirements cannot carry
    /// default argument values; use the 4-argument convenience overload in the
    /// extension below (`forceSave: false`) unless the caller needs to opt into
    /// persisting regardless of an active game (the standalone item editor does).
    @MainActor func insertEntry(itemId: UUID, name: String, content: String, position: SheetInsertionPosition, forceSave: Bool) -> UUID?
    
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
        guard canAddLink(module: module, entryId: entryId) else { return }
        addLinkInEntry(link: link, module: module, itemId: itemId, entryId: entryId, destinationItemId: destinationItemId, destinationEntryId: destinationEntryId)
        MasterRPGTips.recordContentLinked()
    }

    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool { false }

    var canAddGroups: Bool { false }
    var canConvertGroups: Bool { false }

    @MainActor func addNewGroup(itemId: UUID) async -> UUID {
        UUID() // Default implementation does nothing, returns empty UUID
    }

    @MainActor func canBecomeGroup(itemId: UUID) -> Bool { false }

    @MainActor func convertToGroup(itemId: UUID, entryId: UUID, existingItemId: UUID?) async -> UUID {
        UUID() // Default implementation does nothing, returns empty UUID
    }

    @MainActor func canMoveIntoGroup(itemId: UUID, into targetId: UUID) -> Bool { false }

    @MainActor func moveIntoGroup(itemId: UUID, into targetId: UUID) -> UUID? { nil }

    @MainActor func entryContent(itemId: UUID, entryId: UUID) -> String {
        editModel(for: itemId)?[entryId].content ?? ""
    }

    @MainActor func addLinkInEntry(link: String, module: NetworkModules, itemId: UUID, entryId: UUID?, destinationItemId: UUID, destinationEntryId: UUID, separator: String = " ") {
        guard canAddLink(module: module, entryId: entryId), var item = editModel(for: destinationItemId) else { return }
        
        var entry = item[destinationEntryId]
        var content = entry.content.trimmingCharacters(in: .whitespaces)
        
        let nextLinkNumber = LinkReplaceController.links(for: content).filter { $0.itemId == itemId && $0.entryId == entryId }.reduce(-1) { max($0, $1.linkNumber) } + 1
        
        let linkText = "\(content.isEmpty ? "" : separator)" + LinkBuilder.markdown(name: link, module: module, linkNumber: nextLinkNumber, itemId: itemId, entryId: entryId)
        content.append(linkText)
        entry.content = content
        item[destinationEntryId] = entry
        save(updated: item, message: String(localized: "Add Link", bundle: .module))
    }
    
    var thumbnailEntryViewType: ThumbnailEntryViewType { .none }
    func hasThumbnailImage(for entry: any EntryDataAccessible) -> Bool { true }
    var additionalEntryViewType: AdditionalEntryViewType { .none }
    
    @MainActor func additionalRowView(for source: ItemRowModel, entry: any EntryDataAccessible, textModel: LinkHighlightTextModel?) -> AnyView { AnyView(EmptyView()) }
    
    @MainActor func rowText(itemId: UUID, entry: any EntryDataAccessible) -> String {
        entry.name.isEmpty ? entry.content : "\(entry.name.markDownText()): \(entry.content)"
    }
    
    @MainActor func editEntries(for item: Model) -> [Model.Entry] {
        item.entries
    }
    
    @MainActor func addNewEntry(itemId: UUID, forceSave: Bool = false) -> UUID {
        let entry = Model.Entry.empty
        add(entry: entry, itemId: itemId, forceSave: forceSave)
        MasterRPGTips.recordEntryCreated()
        return entry.id
    }

    @MainActor
    func add(entry: Model.Entry, itemId: UUID, forceSave: Bool = false) {
        guard let item = editModel(for: itemId) else { return }
        add(entry: entry, into: item, forceSave: forceSave)
    }

    @MainActor
    func add(entry: Model.Entry, into itemId: UUID, index: Int? = nil, forceSave: Bool = false) {
        guard let editModel = editModel(for: itemId) else { return }
        add(entry: entry, into: editModel, index: index, forceSave: forceSave)
    }

    @MainActor
    private func add(entry: Model.Entry, into item: Model, index: Int? = nil, forceSave: Bool = false) {
        let validatedIndex = index ?? editEntries(for: item).count
        item.entries.insert(entry, at: validatedIndex)
        save(updated: item, message: String(localized: "Add entry", bundle: .module), forceSave: forceSave)
    }

    @MainActor func copy(itemId: UUID, entryIds: [UUID], forceSave: Bool = false) {
        for entryId in entryIds {
            _ = copy(itemId: itemId, entryId: entryId, forceSave: forceSave)
        }
    }

    @MainActor func copy(itemId: UUID, entryId: UUID, forceSave: Bool = false) -> UUID? {
        guard let item = editModel(for: itemId) else { return nil }
        let duplicate = item[entryId].duplicate()
        item.entries.append(duplicate)
        let name = String(duplicate.name.prefix(16))
        save(updated: item, message: String(localized: "Copy entry \(name)", bundle: .module), forceSave: forceSave)
        return duplicate.id
    }

    @MainActor func remove(itemId: UUID, entryIndexSet: IndexSet, forceSave: Bool = false) {
        guard let item = editModel(for: itemId) else { return }
        let ids = entryIndexSet.map { item.entries[$0].id }
        remove(itemId: itemId, entryIds: ids, forceSave: forceSave)
    }

    @MainActor func remove(itemId: UUID, entryIds: [UUID], forceSave: Bool = false) {
        for entryId in entryIds {
            remove(itemId: itemId, entryId: entryId, forceSave: forceSave)
        }
    }

    @MainActor func remove(itemId: UUID, entryId: UUID, forceSave: Bool) {
        guard let item = editModel(for: itemId) else { return }
        guard let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return }
        item.entries.remove(at: index)
        save(updated: item, message: String(localized: "Remove entry", bundle: .module), forceSave: forceSave)
    }

    /// Convenience overload preserving every pre-existing 2-argument call site
    /// (memory-only during an active game, matching historical behavior).
    @MainActor func remove(itemId: UUID, entryId: UUID) {
        remove(itemId: itemId, entryId: entryId, forceSave: false)
    }

    @MainActor func update(itemId: UUID, entryId: UUID, name: String, content: String, forceSave: Bool) {
        updateDefault(itemId: itemId, entryId: entryId, name: name, content: content, nameWithLink: false, forceSave: forceSave)
    }

    /// Convenience overload preserving every pre-existing 4-argument call site
    /// (memory-only during an active game, matching historical behavior).
    @MainActor func update(itemId: UUID, entryId: UUID, name: String, content: String) {
        update(itemId: itemId, entryId: entryId, name: name, content: content, forceSave: false)
    }

    /// Convenience overload preserving every pre-existing 3-argument call site
    /// (memory-only during an active game, matching historical behavior).
    @MainActor func merge(itemId: UUID, entries: [Model.Entry], recoverEntries: [ItemRowModel]?) -> [ItemRowModel] {
        merge(itemId: itemId, entries: entries, recoverEntries: recoverEntries, forceSave: false)
    }

    /// Matches edited entries to the item's existing entries by name, so an entry keeps its id
    /// (and links to it) when only its content changed. Each existing entry is used at most
    /// once: with a plain first match, two entries of the same name collapsed onto one id.
    /// Adventure had this fix, the copies in Map, Table and Character did not.
    /// Names are compared without link markup, so a name that only gained or lost a link keeps its
    /// entry (a map room its outline, a character value its dice and formula) and takes the edited
    /// name. See CODE_AUDIT_Folder §9.10, CODE_AUDIT_Since_3.0.1 §5.1.
    @MainActor func entriesMatchedByName(itemId: UUID, entries: [Model.Entry]) -> [Model.Entry] {
        guard let item = editModel(for: itemId) else { return entries }
        // Only what the editor shows can be matched; hidden entries (e.g. a map's hex grid) keep their own identity.
        var available = editEntries(for: item)
        return entries.map { entry in
            let name = entry.name.withoutLink()
            guard let index = available.firstIndex(where: { $0.name.withoutLink() == name }) else { return entry }
            var matched = available.remove(at: index)
            matched.name = entry.name
            matched.content = entry.content
            return matched
        }
    }

    /// Default `merge(itemId:entries:recoverEntries:forceSave:)`: computes the merged
    /// entries via `merge(itemId:entries:)` (module-specific matching), then applies the
    /// shared "diff removed ids → check link usage → replace-or-report" skeleton that
    /// Character/Adventure/Table each hand-copied identically. A module whose merge
    /// needs genuinely different behavior at this level — RuleRPG's stable-identity +
    /// hierarchy-fallback matching, or MapRPG's deliberate choice not to thread
    /// `forceSave` into the final `save(...)` call — keeps its own override instead of
    /// relying on this default. See CODE_AUDIT_EditItem §9.2.
    @MainActor
    func merge(itemId: UUID, entries: [Model.Entry], recoverEntries: [ItemRowModel]?, forceSave: Bool) -> [ItemRowModel] {
        guard let item = editModel(for: itemId) else { return [] }
        var newEntries = merge(itemId: itemId, entries: entries)
        let removedIds = Set(item.entries.map { $0.id }).subtracting(newEntries.map { $0.id })
        let module = itemControllable.config.module
        let itemRowModels = removedIds.map { ItemRowModel(itemId: item.id, entryId: $0, typeId: module) }

        var affectedLinks = true
        for itemRowModel in itemRowModels {
            if !linkRegisterController.used(for: itemRowModel).isEmpty {
                affectedLinks = false
                break
            }
        }
        if recoverEntries != nil || affectedLinks {
            if let recoverEntries {
                newEntries.append(contentsOf: recoverEntries.compactMap { $0.entryId }.map { item[$0] })
            }
            item.entries = newEntries
            save(updated: item, message: String(localized: "Entries replaced", bundle: .module), forceSave: forceSave)
            return []
        }
        return itemRowModels
    }

    @MainActor
    func insertEntry(itemId: UUID, name: String, content: String, position: SheetInsertionPosition, forceSave: Bool) -> UUID? {
        guard let item = editModel(for: itemId) else { return nil }

        let entry = create(name: name, content: content)
        let insertionIndex: Int
        switch position {
        case .end:
            insertionIndex = item.entries.count
        case .after(let anchorEntryId):
            insertionIndex = item.entries.firstIndex(where: { $0.id == anchorEntryId })
                .map { $0 + 1 } ?? item.entries.count
        }

        add(entry: entry, into: itemId, index: insertionIndex, forceSave: forceSave)
        return entry.id
    }

    /// Convenience overload preserving every pre-existing 4-argument call site
    /// (memory-only during an active game, matching historical behavior).
    @MainActor
    func insertEntry(itemId: UUID, name: String, content: String, position: SheetInsertionPosition) -> UUID? {
        insertEntry(itemId: itemId, name: name, content: content, position: position, forceSave: false)
    }

    @MainActor func updateDefault(itemId: UUID, entryId: UUID, name: String, content: String, nameWithLink: Bool, forceSave: Bool = false) {
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
            // `.replacing(_:with:subrange:)` was tried here first but discovered (via a
            // failing test) to replace every occurrence in the whole string, silently
            // ignoring `subrange`, in this Swift toolchain — not a scoped search at all.
            // `replaceSubrange(_:with:)` unambiguously replaces only this exact range.
            newContent.replaceSubrange(range, with: newLink.markDown ?? oldLinkText)
            linkRegisterController.register(links: [newLink])
        }
        changed = changed || item[entryId].content != newContent
        item[entryId].content <=> newContent
        if changed {
            cacheItemListModel.reset(cacheType: .row, itemId: entryId, text: rowText(itemId: item.id, entry: item[entryId]))
        }
        save(updated: item, message: String(localized: "Edit entry", bundle: .module), forceSave: forceSave)
    }

    @MainActor func move(itemId: UUID, entryIds: [UUID], forceSave: Bool = false) {
        guard let item = editModel(for: itemId) else { return }
        let entries = entryIds.compactMap { id in item.entries.first { $0.id == id }}
        item.entries = entries
        save(updated: item, message: String(localized: "Reorder entries", bundle: .module), forceSave: forceSave)
    }

    @MainActor func move(itemId: UUID, entryId: UUID, up: Bool, forceSave: Bool = false) {
        guard let item = editModel(for: itemId) else { return }
        guard let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return }
        if up {
            guard index > 0 else { return }
            item.entries.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        } else {
            guard index < item.entries.count - 1 else { return }
            item.entries.move(fromOffsets: IndexSet(integer: index + 1), toOffset: index)
        }
        save(updated: item, message: String(localized: up ? "Move entry up" : "Move entry down", bundle: .module), forceSave: forceSave)
    }

    @MainActor func move(itemId: UUID, entryId: UUID, into: ItemRowModel, forceSave: Bool = false) -> Bool {
        guard let item = editModel(for: into.itemId) else { return false }
        guard let otherItem = editModel(for: itemId), let index = otherItem.entries.firstIndex(where: { $0.id == entryId }) else { return false }
        let entry = otherItem.entries.remove(at: index)
        item.entries.append(entry)
        save(updated: otherItem, message: String(localized: "remove entry", bundle: .module), forceSave: forceSave)
        save(updated: item, message: String(localized: "add entry", bundle: .module), forceSave: forceSave)
        return true
    }

    @MainActor func groupFolders(itemId: UUID, sourceEntryId: UUID) -> [FolderRepresentable] { [] }

    @MainActor func move(itemId: UUID, sourceEntryId: UUID, into folder: FolderRepresentable, forceSave: Bool = false) {
        guard let item = editModel(for: itemId), let group = editModel(for: folder.id) else { return }
        let entry = item[sourceEntryId]
        item.entries.removeAll(where: { $0.id == sourceEntryId })
        group.entries.append(entry)
        save(updated: item, message: String(localized: "remove entry", bundle: .module), forceSave: forceSave)
        save(updated: group, message: String(localized: "move entry", bundle: .module), forceSave: forceSave)
    }

    @MainActor func parentFolder(itemId: UUID) -> FolderRepresentable? { nil }
    @MainActor func isValueGroupParent(itemId: UUID) -> Bool { true }

    @MainActor func moveOutOfGroup(itemId: UUID, sourceEntryId: UUID, parent: FolderRepresentable, forceSave: Bool = false) {
        guard let group = editModel(for: itemId), let parentItem = editModel(for: parent.id) else { return }
        let entry = group[sourceEntryId]
        group.entries.removeAll(where: { $0.id == sourceEntryId })
        parentItem.entries.append(entry)
        save(updated: group, message: String(localized: "remove entry", bundle: .module), forceSave: forceSave)
        save(updated: parentItem, message: String(localized: "move entry out", bundle: .module), forceSave: forceSave)
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
    @MainActor func linkTextModel(itemId: UUID, for entry: any EntryDataAccessible, linkController: any LinkControllable, cacheItemListModel: CacheItemListModel, searchModel: SearchModel, toggler: ((UUID, NetworkModules, Int) async -> Void)? = nil) -> LinkHighlightTextModel {
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
}
