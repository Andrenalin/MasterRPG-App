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

    /// Merges imported entries into the existing ones, keeping the identity of entries that are
    /// still there.
    ///
    /// Two passes: every imported entry first claims the existing entry with its own id. Only the
    /// leftovers then try the name + kind + parent fallback, and only against existing entries no
    /// id match claimed. In a single pass a new entry listed before the existing entry it
    /// resembles took that entry's identity through the fallback, and the existing entry (same id)
    /// then appeared a second time. See CODE_AUDIT_26 §5.43.
    static func mergeEntries(
        existing: [RuleEntryModel],
        imported: [RuleEntryModel]
    ) -> [RuleEntryModel] {
        var matchedExistingIndices: Set<Int> = []
        var importedToExistingIds: [UUID: UUID] = [:]
        var idMatches: [Int: Int] = [:]

        // Existing entries by id (in order, ids can repeat) and, built only when the first
        // fallback is needed, by name without link + kind + parent. The lookups ran a linear
        // search with a string transform per candidate for every imported entry.
        // See CODE_AUDIT_26 §7.22.
        var existingIndicesById: [UUID: [Int]] = [:]
        for (index, entry) in existing.enumerated() {
            existingIndicesById[entry.id, default: []].append(index)
        }
        var idCursors: [UUID: Int] = [:]

        for (importedIndex, entry) in imported.enumerated() {
            guard let candidates = existingIndicesById[entry.id] else { continue }
            let cursor = idCursors[entry.id, default: 0]
            guard cursor < candidates.count else { continue }
            idCursors[entry.id] = cursor + 1
            let existingIndex = candidates[cursor]
            matchedExistingIndices.insert(existingIndex)
            idMatches[importedIndex] = existingIndex
            importedToExistingIds[entry.id] = existing[existingIndex].id
        }

        struct FallbackKey: Hashable {
            let name: String
            let kind: RuleEntryKind
            let parentId: UUID?
        }
        var fallbackIndices: [FallbackKey: [Int]]?

        return imported.enumerated().map { importedIndex, sourceEntry in
            var importedEntry = sourceEntry
            if let parentId = importedEntry.parentId,
               let remappedParentId = importedToExistingIds[parentId] {
                importedEntry.parentId = remappedParentId
            }

            let matchedIndex: Int?
            if let idMatch = idMatches[importedIndex] {
                matchedIndex = idMatch
            } else {
                // Compared without link markup, as `entriesMatchedByName` does: a name that only
                // gained a link is the same entry. See CODE_AUDIT_Since_3.0.1 §5.1.
                if fallbackIndices == nil {
                    var index: [FallbackKey: [Int]] = [:]
                    for (existingIndex, entry) in existing.enumerated() {
                        index[FallbackKey(name: entry.name.withoutLink(), kind: entry.kind, parentId: entry.parentId), default: []].append(existingIndex)
                    }
                    fallbackIndices = index
                }
                let key = FallbackKey(name: importedEntry.name.withoutLink(), kind: importedEntry.kind, parentId: importedEntry.parentId)
                let hierarchyFallbackIndices = (fallbackIndices?[key] ?? []).filter { !matchedExistingIndices.contains($0) }
                matchedIndex = hierarchyFallbackIndices.count == 1 ? hierarchyFallbackIndices[0] : nil
                if let matchedIndex {
                    matchedExistingIndices.insert(matchedIndex)
                }
            }
            guard let matchedIndex else {
                importedToExistingIds[sourceEntry.id] = importedEntry.id
                return importedEntry
            }

            var mergedEntry = existing[matchedIndex]
            importedToExistingIds[sourceEntry.id] = mergedEntry.id
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
        recoverEntries: [ItemRowModel]?,
        forceSave: Bool
    ) -> [ItemRowModel] {
        guard let item = editModel(for: itemId) else { return [] }
        var merged = merge(itemId: itemId, entries: entries)
        let removedIds = Set(item.entries.map(\.id)).subtracting(merged.map(\.id))
        let removedRows = removedIds.map {
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
        save(updated: item, message: String(localized: "Rule sections replaced", bundle: .ruleModule), forceSave: forceSave)
        return []
    }

    @MainActor
    func reset(sourceMetadata: RuleSourceMetadata, itemId: UUID) {
        guard let item = editModel(for: itemId), item.sourceMetadata != sourceMetadata else { return }
        item.sourceMetadata = sourceMetadata
        save(updated: item, message: String(localized: "Rule source updated", bundle: .ruleModule))
    }
}
