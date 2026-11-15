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
    @MainActor init(itemController: ItemController, tagController: TagController) {
        self.tagController = tagController
        self.itemController = itemController
        let sheetEditorModel = SheetEditorModel(module: itemController.config.module)
        let editorModel = ItemEditorModel(sheetEditorModel: sheetEditorModel)
        self.editorModel = editorModel
        self.adventureEditModel = AdventureEditModel()
    }

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

// The group functions (`addNewGroup`, `convertToGroup`, …) and `isOrphanedHidden`/
// `willRepairOrphan`/`willRestore` are the shared `GroupableModel`-constrained defaults.
// See CODE_AUDIT_EditItem §9.5, CODE_AUDIT_Folder §9.9.

// MARK: - Duplicate with sub-groups

extension EditController {
    @MainActor public func duplicate(item: any ItemDataAccessible) async {
        guard let model = folderEditModel(for: item.id, scope: .library) else { return }
        let copyId = storeSubAdventureCopies(of: model, withCopy: true, parentId: nil)

        // A folder's members get independent copies too, all the way down. Its member entries
        // (`entry.childId`) are not the "convert to group" links (`entry.adventureId`) that
        // `duplicateSubAdventure` follows. See CODE_AUDIT_EditItem §5.3.
        if model.isFolder {
            await duplicateFolderMembers(of: model.id, into: copyId) { member, parentId in
                storeSubAdventureCopies(of: member, withCopy: false, parentId: parentId)
            }
        }
        placeDuplicate(copyId, of: model)
    }

    /// Copies `model` with its groups and stores every copy; returns the copy's id. Persisted
    /// also during a running game. See CODE_AUDIT_Folder §5.21.
    @MainActor private func storeSubAdventureCopies(of model: AdventureModel, withCopy: Bool, parentId: UUID?) -> UUID {
        let (copies, copyId) = duplicateSubAdventure(model: model, withCopy: withCopy, parentId: parentId, visited: [model.id])
        for copy in copies {
            itemControllable.replace(model: copy, isInsert: true, forceSave: true)
        }
        return copyId
    }

    /// The copy gets its folder parent before it is stored: setting it on the stored instance
    /// afterwards is never persisted. See CODE_AUDIT_Folder §5.5.
    @MainActor private func duplicateSubAdventure(model: AdventureModel, withCopy: Bool, parentId: UUID?, visited: Set<UUID>) -> ([AdventureModel], UUID) {
        let copyItem = withCopy ? model.duplicate() : model.duplicateWithoutCopy()
        copyItem.parentId = parentId
        var copies: [AdventureModel] = [copyItem]
        if model.category.isCollection {
            // A collection's copy references the same members. See CODE_AUDIT_Folder §5.16.
            copyItem.entries = model.entries.map { Model.Entry.newChild(id: $0.childId) }
            return (copies, copyItem.id)
        }
        var newEntries: [AdventureEntryModel] = []
        for entry in model.entries {
            var duplicatedEntry = entry.duplicate()
            if let adventureId = entry.adventureId, !visited.contains(adventureId),
               let childModel = itemControllable.itemSync(for: adventureId, noGame: true) as? AdventureModel {
                var visited = visited
                visited.insert(adventureId)
                let (childCopies, childCopyId) = duplicateSubAdventure(model: childModel, withCopy: false, parentId: nil, visited: visited)
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
        save(updated: item, message: String(localized: "Change Dice", bundle: .module))
    }

    @MainActor func add(photoId: UUID?, itemId: UUID) {
        guard let item = editModel(for: itemId) else { return }
        item.photoId = photoId
        save(updated: item, message: String(localized: "Changed Photo", bundle: .module))
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
        entriesMatchedByName(itemId: itemId, entries: entries)
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
