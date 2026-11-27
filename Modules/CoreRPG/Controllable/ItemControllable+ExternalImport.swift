// @copyright André Trettin

import Foundation
import Observation
import os.log

// The external-import staging, split out of ItemControllable.swift. See CODE_AUDIT_29 §9.9.

public extension ItemControllable {
    /// Stages one exact model snapshot for an external-import transaction and
    /// surfaces persistence errors to the caller. This deliberately does not
    /// change the best-effort behaviour of the general editor API in `ItemControllable.swift`.
    @MainActor func replaceForExternalImport(
        model: any ModelType,
        isInsert: Bool
    ) throws {
        guard let model = model as? Model else {
            throw ItemTransactionMutationError.incompatibleModel
        }

        let snapshot = model.copy()
        let existing = itemSync(for: snapshot.id, noGame: true)
        if existing != nil || isInsert {
            itemDataModel.markIndexDirty(snapshot.id)
            try dataControllable?.replaceSync(id: snapshot.id, with: snapshot)
            if existing == nil {
                dataControllable?.markUnsavedInsert(id: snapshot.id)
            }
        }

        if let existing {
            let needsResort = existing.name != snapshot.name
            setModel(with: snapshot)
            if needsResort {
                resortItem(changed: snapshot)
            }
        } else {
            resetModel(with: snapshot)
        }
    }

    /// Removes an item as part of external-import rollback while keeping the
    /// binary intact. Database staging happens before the in-memory removal so a
    /// thrown error never masquerades as a successful rollback.
    @MainActor func deleteForExternalImport(itemId: UUID) async throws {
        guard let item = itemSync(for: itemId, noGame: true) else { return }
        // A failed consolidated save re-queues the import's own insert; drop it, or the
        // rollback's second save commits the item the import just rolled back.
        // See CODE_AUDIT_19 §5.1.
        await dataControllable?.removePendingOperations(for: item.id)
        do {
            try await dataControllable?.delete(id: item.id)
        } catch {
            // The failed flush queued the deletion again, and the item stays in memory.
            // See CODE_AUDIT_28 §5.5.
            await dataControllable?.removePendingOperations(for: item.id)
            throw error
        }

        for entry in item.entries {
            await cacheControllable?.remove(itemId: entry.id)
        }
        if let fileUrl = item.fileUrl {
            await cacheControllable?.remove(itemId: itemId)
            fileUrlDataController?.removeBookmarks(fileId: fileUrl.fileId)
        }
        itemDataModel.resetModel(id: item.id)
    }

    /// Exact copies of the current library models used to cover repair effects
    /// that can reach parents or children outside the selected import batch.
    @MainActor func externalImportSnapshots(ids: Set<UUID>) -> [UUID: any ModelType] {
        ids.reduce(into: [:]) { snapshots, itemId in
            if let item = itemSync(for: itemId, noGame: true) {
                snapshots[itemId] = item.copy()
            }
        }
    }

    /// The items outside `importedIds` that the import repair (`ConvertController`) can change:
    /// the folder parent each imported item may be removed from, and the entry children whose
    /// display state an un-grouping resets. Snapshotting only these keeps a rollback from
    /// reverting unrelated items of the module. See CODE_AUDIT_Folder §3.6.
    @MainActor func externalImportRepairScope(importedIds: Set<UUID>) -> Set<UUID> {
        var scope: Set<UUID> = []
        for itemId in importedIds {
            guard let item = itemSync(for: itemId, noGame: true) else { continue }
            if let parentId = item.parentId {
                scope.insert(parentId)
            }
            scope.formUnion(item.entries.map(\.childId))
        }
        return scope.subtracting(importedIds).filter { itemSync(for: $0, noGame: true) != nil }
    }
}
