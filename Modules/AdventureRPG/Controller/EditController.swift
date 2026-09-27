// @copyright André Trettin

import CoreRPG
import Foundation
#if !os(tvOS)
import GeneratorRPG
#endif
import Observation
import SwiftUI
import AudioRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG

@MainActor @Observable
final class AdventureEditModel: Sendable {
    // Only these 3 drive real drop-section UI (DiceDropSection/PhotoDropSection,
    // QuickEntryEditor); the other 6 module selections this type used to carry
    // (audio/character/map/space/table/weather) were dead state with no consumer
    // anywhere in the module. See CODE_AUDIT §9.3.
    let selectionDice: ItemSelectionModel = ItemSelectionModel()
    let selectionPdf: ItemSelectionModel = ItemSelectionModel()
    let selectionPhoto: ItemSelectionModel = ItemSelectionModel()
}

struct LinkAdventureModuleTransferable: LinkDataTransferable {
    let module: NetworkModules
    let itemId: UUID
    let entryId: UUID?
    let name: String
    let isMove: Bool

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .adventureLink)
        CodableRepresentation(contentType: .audioLink)
        CodableRepresentation(contentType: .characterLink)
        CodableRepresentation(contentType: .diceLink)
        CodableRepresentation(contentType: .mapLink)
        CodableRepresentation(contentType: .pdfLink)
        CodableRepresentation(contentType: .photoLink)
        CodableRepresentation(contentType: .ruleLink)
        CodableRepresentation(contentType: .spaceLink)
        AdventureSupplementalLinkRepresentations()
    }
}

private struct AdventureSupplementalLinkRepresentations: TransferRepresentation {
    typealias Item = LinkAdventureModuleTransferable

    var body: some TransferRepresentation {
        CodableRepresentation(contentType: .tableLink)
        CodableRepresentation(contentType: .weatherLink)
    }
}

struct EditController: Sendable {
    @MainActor init(root: AdventureRootModel, itemController: ItemController, linkController: LinkController, sheetController: SheetController, tagController: TagController) {
        self.root = root
        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
        self.adventureEditModel = AdventureEditModel()
    }

    let root: AdventureRootModel

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
    let adventureEditModel: AdventureEditModel
}

extension EditController: EntryDataEditable {
    typealias Model = AdventureModel

    var itemControllable: any ItemControllable {
        itemController
    }

    var canAddGroups: Bool { true }
    var canConvertGroups: Bool { true }
}
    
// MARK: - EntryList editor

extension EditController {
    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        true
    }

    @MainActor public func update(itemId: UUID, entryId: UUID, name: String, content: String, forceSave: Bool) {
        guard let item = editModel(for: itemId) else { return }
        if let adventureId = item[entryId].adventureId {
            reset(name: name, itemId: adventureId, forceSave: forceSave)
            reset(description: content, itemId: adventureId, forceSave: forceSave)
        } else {
            updateDefault(itemId: itemId, entryId: entryId, name: name, content: content, nameWithLink: false, forceSave: forceSave)
        }
    }

    public var linkModules: [NetworkModules] { [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .rule, .space, .table, .weather] }
    
    public func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        AdventureEditorRoute.linkSelection(itemRowModel)
    }
}

// MARK: - Group Management

extension EditController {
    @MainActor func addNewGroup(itemId: UUID) async -> UUID {
        let groupId = await itemController.addNew(type: .item)
        reset(hidden: true, itemId: groupId)
        guard let group = editModel(for: groupId) else { return groupId }
        group.groupId = itemId
        save(updated: group, message: String(localized: "prepare group", bundle: .module).localizedString)
        var entry = Model.Entry.empty
        entry.name = group.name
        entry.adventureId = groupId
        add(entry: entry, itemId: itemId)
        return entry.id
    }

    @MainActor func canBecomeGroup(itemId: UUID) -> Bool {
        guard let item = itemControllable.itemSync(for: itemId) as? AdventureModel else { return false }
        return item.groupId == nil
    }

    @MainActor func convertToGroup(itemId: UUID, entryId: UUID, existingItemId: UUID?) async -> UUID {
        guard let item = editModel(for: itemId), let index = item.entries.firstIndex(where: { $0.id == entryId }) else { return UUID() }

        let groupId: UUID        
        if let existingItemId, let existingGroup = editModel(for: existingItemId) {
            groupId = existingItemId
            existingGroup.groupId = itemId
            existingGroup.isGroupHiddenToggle = true
            save(updated: existingGroup, message: String(localized: "prepare group", bundle: .module).localizedString)
            item.entries[index].name = existingGroup.name
            item.entries[index].content = existingGroup.description
        } else {
            groupId = await itemController.addNew(type: .item)
            reset(hidden: true, itemId: groupId)
            guard let group = editModel(for: groupId) else { return groupId }
            group.name = item.entries[index].name.withoutLink()
            group.description = item.entries[index].content
            group.groupId = itemId
            save(updated: group, message: String(localized: "prepare group", bundle: .module).localizedString)
        }
        item.entries[index].adventureId = groupId
        save(updated: item, message: String(localized: "Convert to group", bundle: .module).localizedString)
        return groupId
    }

    @MainActor func groupFolders(itemId: UUID, sourceEntryId: UUID) -> [FolderRepresentable] {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return [] }
        return item.entries.compactMap {
            guard $0.id != sourceEntryId, let adventureId = $0.adventureId else { return nil }
            return FolderRepresentable(id: adventureId, name: $0.name)
        }
    }

    @MainActor func parentFolder(itemId: UUID) -> FolderRepresentable? {
        guard let item = itemControllable.itemSync(for: itemId) as? Model else { return nil }
        let resolvedParentId = item.groupId ?? item.parentId
        guard let resolvedParentId, let parent = itemControllable.itemSync(for: resolvedParentId) as? Model else { return nil }
        return FolderRepresentable(id: parent.id, name: parent.name)
    }

    // `isOrphanedHidden`/`willRepairOrphan`/`willRestore` use `EditControllable`'s
    // shared `GroupableModel`-constrained default now that `AdventureModel` conforms to
    // `GroupableModel` — see CODE_AUDIT_EditItem §9.5.

    @MainActor func willDeleteChildren(of item: AdventureModel) async {
        guard item.category != .folder else { return }
        for entry in item.entries {
            guard let adventureId = entry.adventureId else { continue }
            await Task.yield()
            await delete(itemId: adventureId)
        }
    }
}

// MARK: - Duplicate with sub-groups

extension EditController {
    @MainActor public func duplicate(item: any ItemDataAccessible) async {
        guard let model = editModel(for: item.id) else { return }
        let originalParentId = model.parentId
        let (copies, copyId) = duplicateSubAdventure(model: model, withCopy: true, visited: [model.id])
        for copy in copies {
            itemControllable.replace(model: copy, isInsert: true)
        }

        // For folders: rebuild entries with independent, recursively-duplicated child
        // copies. `duplicateSubAdventure` above only follows the unrelated
        // `entry.adventureId` "convert to group" relationship — a folder's actual
        // membership entries (`entry.childId == entry.id`) were otherwise left as the
        // plain `entry.duplicate()` produced by `AdventureModel.duplicate()`, which
        // mints a new random `id` and so pointed at nothing. See
        // CODE_AUDIT_EditItem §5.3.
        if item.isFolder, let copyFolder = editModel(for: copyId) {
            copyFolder.entries = await duplicateFolderEntries(of: item.id, newParentId: copyId, visited: [item.id])
            save(updated: copyFolder, message: String(localized: "Duplicate folder", bundle: .module).localizedString)
        }

        if let parentId = originalParentId {
            addItem(itemId: copyId, parentId: parentId)
        }
        let originalId = item.id
        for containerId in itemControllable.itemDataModel.items {
            guard let container = itemControllable.itemSync(for: containerId),
                  container.category == itemControllable.collectionCategory,
                  container.entries.contains(where: { $0.childId == originalId }) else { continue }
            addGroup(itemId: containerId, childId: copyId)
        }
    }

    /// Recursively duplicates every folder-membership child of `originalFolderId`
    /// (`entry.childId`, distinct from the `entry.adventureId` "convert to group"
    /// relationship `duplicateSubAdventure` handles), reparenting each copy under
    /// `newParentId`, and recursing into any child that is itself a folder so nested
    /// folder structures get independent copies all the way down. See
    /// CODE_AUDIT_EditItem §5.3.
    ///
    /// `visited` guards against a self-referential folder/group hierarchy (e.g. from
    /// corrupted sync data) recursing forever — mirrors the same fix applied to
    /// `LinkController.collectLinks`. See CODE_AUDIT §5.7.
    @MainActor private func duplicateFolderEntries(of originalFolderId: UUID, newParentId: UUID, visited: Set<UUID>) async -> [AdventureEntryModel] {
        guard let originalFolder = editModel(for: originalFolderId) else { return [] }
        var newEntries: [AdventureEntryModel] = []
        for entry in originalFolder.entries {
            guard !visited.contains(entry.childId), let childModel = editModel(for: entry.childId) else { continue }
            var visited = visited
            visited.insert(entry.childId)
            let (childCopies, childCopyId) = duplicateSubAdventure(model: childModel, withCopy: false, visited: visited)
            for copy in childCopies {
                itemControllable.replace(model: copy, isInsert: true)
            }
            if let childCopy = editModel(for: childCopyId) {
                childCopy.parentId = newParentId
                if childModel.isFolder {
                    childCopy.entries = await duplicateFolderEntries(of: childModel.id, newParentId: childCopyId, visited: visited)
                }
                save(updated: childCopy, message: String(localized: "Duplicate child", bundle: .module).localizedString)
            }
            newEntries.append(Model.Entry.newChild(id: childCopyId))
        }
        return newEntries
    }

    @MainActor private func duplicateSubAdventure(model: AdventureModel, withCopy: Bool, visited: Set<UUID>) -> ([AdventureModel], UUID) {
        let copyItem = withCopy ? model.duplicate() : model.duplicateWithoutCopy()
        var copies: [AdventureModel] = [copyItem]
        var newEntries: [AdventureEntryModel] = []
        for entry in model.entries {
            var duplicatedEntry = entry.duplicate()
            if let adventureId = entry.adventureId, !visited.contains(adventureId),
               let childModel = itemControllable.itemSync(for: adventureId) as? AdventureModel {
                var visited = visited
                visited.insert(adventureId)
                let (childCopies, childCopyId) = duplicateSubAdventure(model: childModel, withCopy: false, visited: visited)
                childCopies.first?.groupId = copyItem.id
                copies.append(contentsOf: childCopies)
                duplicatedEntry.adventureId = childCopyId
            }
            newEntries.append(duplicatedEntry)
        }
        copyItem.entries = newEntries
        return (copies, copyItem.id)
    }
}

// MARK: - New Editor Functions

extension EditController {
    @MainActor func add(diceId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.diceId = diceId
        save(updated: item, message: String(localized: "Change Dice", bundle: .module).localizedString)
    }

    @MainActor func add(photoId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = photoId
        save(updated: item, message: String(localized: "Changed Photo", bundle: .module).localizedString)
    }
}

// MARK: - Quick Link Editor

extension EditController {
    func create(name: String, content: String) -> AdventureEntryModel {
        AdventureEntryModel(id: UUID(), name: name, content: content)
    }

    /// Matches by `name`, not `id`, because `entries` is freshly re-parsed from raw text on
    /// every edit (see `QuickEntryEditorView`'s `createMultiLineEntries`) and so never
    /// carries over the original entry's `id` — name is the only stable key available to
    /// preserve an entry's identity across parses. Each existing entry is consumed at most
    /// once (`remove(at:)`) so two incoming entries that happen to share a name (e.g. two
    /// "Room" headings) don't both collapse onto the same existing `id` — previously the
    /// second one silently overwrote the first's content under one shared id. See
    /// CODE_AUDIT §5.4.
    @MainActor func merge(itemId: UUID, entries: [AdventureEntryModel]) -> [AdventureEntryModel] {
        guard let item = editModel(for: itemId) else { return entries }
        var availableEntries = item.entries
        return entries.map { entry in
            guard let index = availableEntries.firstIndex(where: { $0.name == entry.name }) else { return entry }
            var foundEntry = availableEntries.remove(at: index)
            foundEntry.content = entry.content
            return foundEntry
        }
    }
    // `merge(itemId:entries:recoverEntries:forceSave:)` uses `EntryDataEditable`'s
    // shared default (see CODE_AUDIT_EditItem §9.2) — this module's behavior was
    // identical to the default (the only difference, `root.itemController.config.module`
    // vs. the default's `itemControllable.config.module`, resolves to the same value),
    // so the hand-copied override was removed.

    public func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        AdventureEditorRoute.quickEditor(itemRowModel.itemId)
    }
}

// MARK: - AI Extraction

#if !os(tvOS)
extension EditController {
    @MainActor func applyExtractedContent(_ content: TableSummaryAnalysis, to itemId: UUID, selection: TextSummaryPropertySelection) {
        if selection.applyTitle {
            reset(name: content.title, itemId: itemId)
        }
        if selection.applyDescription {
            reset(description: content.description, itemId: itemId)
        }
        if selection.applyTags {
            reset(tags: content.tags, itemId: itemId)
        }
    }
}
#endif

extension EditController {

    @MainActor func collectPhotos(itemId: UUID, entryId: UUID) {
        let photoIds = root.linkController.collectLinks(of: .photo, from: itemId)
        let links = photoIds.map {
            root.photoRoot.linkControllable.generateLink(itemId: $0)
        }.sorted()
        update(itemId: itemId, entryId: entryId, name: "Collection", content: links.joined(separator: "\n"))
    }
}
