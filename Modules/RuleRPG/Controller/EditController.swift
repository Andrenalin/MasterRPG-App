// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI

/// Accepts links dragged from every content module supported by the Rule editor.
///
/// `TransferRepresentationBuilder` has a ten-expression limit, so the final two
/// representations live in a nested builder just like AdventureRPG's aggregate type.
struct LinkRuleModuleTransferable: LinkDataTransferable {
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
        RuleSupplementalLinkRepresentations()
    }
}

private struct RuleSupplementalLinkRepresentations: TransferRepresentation {
    typealias Item = LinkRuleModuleTransferable

    var body: some TransferRepresentation {
        CodableRepresentation(contentType: .tableLink)
        CodableRepresentation(contentType: .weatherLink)
    }
}

struct EditController: Sendable {
    @MainActor
    init(
        itemController: ItemController,
        tagController: TagController
    ) {
        self.itemController = itemController
        self.tagController = tagController
        editorModel = ItemEditorModel(
            sheetEditorModel: SheetEditorModel(module: itemController.config.module)
        )
    }

    let itemController: ItemController
    let tagController: TagController
    let editorModel: ItemEditorModel
}

extension EditController: EntryDataEditable {
    typealias Model = RuleModel

    var itemControllable: any ItemControllable { itemController }

    @MainActor
    var linkRegisterController: LinkRegisterController {
        itemController.linkRegisterController
    }

    var linkModules: [NetworkModules] {
        [.adventure, .audio, .value, .dice, .map, .pdf, .photo, .rule, .space, .table, .weather]
    }

    func canAddLink(module: NetworkModules, entryId: UUID?) -> Bool {
        linkModules.contains(module)
    }

    func linkSelectionDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        RuleEditorRoute.linkSelection(itemRowModel)
    }

    func quickEditorDestination(itemRowModel: ItemRowModel) -> any NavigationDestination {
        RuleEditorRoute.quickEditor(itemRowModel.itemId)
    }

    func create(name: String, content: String) -> RuleEntryModel {
        RuleEntryModel(id: UUID(), name: name, content: content)
    }

    @MainActor
    func merge(itemId: UUID, entries: [RuleEntryModel]) -> [RuleEntryModel] {
        guard let item = editModel(for: itemId) else { return entries }
        return Self.mergeEntries(existing: item.entries, imported: entries)
    }

    static func mergeEntries(
        existing: [RuleEntryModel],
        imported: [RuleEntryModel]
    ) -> [RuleEntryModel] {
        var matchedExistingIndices: Set<Int> = []
        var importedToExistingIDs: [UUID: UUID] = [:]

        return imported.map { sourceEntry in
            var importedEntry = sourceEntry
            if let parentId = importedEntry.parentId,
               let remappedParentId = importedToExistingIDs[parentId] {
                importedEntry.parentId = remappedParentId
            }

            let stableIdentityIndex = existing.indices.first {
                !matchedExistingIndices.contains($0) && existing[$0].id == importedEntry.id
            }
            let hierarchyFallbackIndices = existing.indices.filter {
                !matchedExistingIndices.contains($0) &&
                existing[$0].name == importedEntry.name &&
                existing[$0].kind == importedEntry.kind &&
                existing[$0].parentId == importedEntry.parentId
            }
            let matchedIndex = stableIdentityIndex ?? (
                hierarchyFallbackIndices.count == 1 ? hierarchyFallbackIndices[0] : nil
            )
            guard let matchedIndex else {
                importedToExistingIDs[sourceEntry.id] = importedEntry.id
                return importedEntry
            }

            matchedExistingIndices.insert(matchedIndex)
            var mergedEntry = existing[matchedIndex]
            importedToExistingIDs[sourceEntry.id] = mergedEntry.id
            mergedEntry.name = importedEntry.name
            mergedEntry.content = importedEntry.content
            mergedEntry.kind = importedEntry.kind
            mergedEntry.displayState = importedEntry.displayState
            mergedEntry.parentId = importedEntry.parentId
            return mergedEntry
        }
    }

    @MainActor
    func merge(
        itemId: UUID,
        entries: [RuleEntryModel],
        recoverEntries: [ItemRowModel]?
    ) -> [ItemRowModel] {
        guard let item = editModel(for: itemId) else { return [] }
        var merged = merge(itemId: itemId, entries: entries)
        let removedIDs = Set(item.entries.map(\.id)).subtracting(merged.map(\.id))
        let removedRows = removedIDs.map {
            ItemRowModel(itemId: item.id, entryId: $0, typeId: .rule)
        }
        let hasAffectedLinks = removedRows.contains { row in
            !linkRegisterController.used(for: row).isEmpty
        }

        guard recoverEntries != nil || !hasAffectedLinks else { return removedRows }
        if let recoverEntries {
            merged.append(contentsOf: recoverEntries.compactMap(\.entryId).map { item[$0] })
        }
        item.entries = merged
        save(updated: item, message: String(localized: "Rule sections replaced", bundle: .ruleModule))
        return []
    }

    @MainActor
    func reset(sourceMetadata: RuleSourceMetadata, itemId: UUID) {
        guard let item = editModel(for: itemId), item.sourceMetadata != sourceMetadata else { return }
        item.sourceMetadata = sourceMetadata
        save(updated: item, message: String(localized: "Rule source updated", bundle: .ruleModule))
    }

    @MainActor
    func reset(kind: RuleEntryKind, itemId: UUID, entryId: UUID) {
        guard let item = editModel(for: itemId), item[entryId].kind != kind else { return }
        var entry = item[entryId]
        entry.kind = kind
        item[entryId] = entry
        save(updated: item, message: String(localized: "Rule section type updated", bundle: .ruleModule))
    }
}
