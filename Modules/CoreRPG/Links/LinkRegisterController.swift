// @copyright André Trettin

import CoreData
import Foundation
import os.log

/// Two-layer cross-module link registry: in-memory (`LinkRegisterListModel`) backed by CoreData (`LinkReferenceDataModel`).
///
/// Links are indexed by both `destination.itemId` and `source.itemId`. Registration happens on every item save (via `EditControllable`),
/// on inline editor link insertion, and on import. The register is rebuilt from CoreData on `setup(context:)`.
/// Use `linksFrom(source:)` in SheetControllers for O(1) outgoing-link lookup instead of re-parsing entry text.
@MainActor public struct LinkRegisterController: Sendable {
    public init(root: RootManager?) {
        self.root = root
        self.model = LinkRegisterListModel()
    }

    let root: RootManager?
    @MainActor public let model: LinkRegisterListModel

    /// Fetches all persisted `LinkReferenceDataModel` rows from CoreData and populates both indexes. Call once on startup.
    /// Returns the running task so a caller that needs rehydration to actually finish
    /// before allowing edits that register links (e.g. right after launch) can await it.
    @discardableResult
    @MainActor public func setup(context: NSManagedObjectContext?) -> Task<Void, Never>? {
        guard let context else { return nil }
        model.context = context

        return Task(priority: .userInitiated) {
            let parsedModels: [LinkRegisterModel] = await context.perform {
                do {
                    let request: NSFetchRequest<NSFetchRequestResult> = LinkReferenceDataModel.fetchRequest()
                    // Grows with every cross-item link reference in every module; batch the
                    // fetch instead of materializing the whole table at once.
                    request.fetchBatchSize = 500
                    guard let linkReferenceModels = try context.fetch(request) as? [LinkReferenceDataModel] else { return [] }
                    var nextLegacyOccurrence: [LegacyLinkKey: Int] = [:]
                    var results: [LinkRegisterModel] = []
                    results.reserveCapacity(linkReferenceModels.count)
                    for linkReferenceModel in linkReferenceModels {
                        let source = ItemRowModel(itemId: linkReferenceModel.sourceId ?? UUID(), entryId: linkReferenceModel.sourceEntryId, typeId: NetworkModules(rawValue: Int(linkReferenceModel.sourceModule)) ?? .none)
                        let destination = ItemRowModel(itemId: linkReferenceModel.destinationId ?? UUID(), entryId: linkReferenceModel.destinationEntryId, typeId: NetworkModules(rawValue: Int(linkReferenceModel.destinationModule)) ?? .none)

                        let name = linkReferenceModel.name ?? ""
                        let linkNumber: Int?
                        if linkReferenceModel.linkNumber >= 0 {
                            linkNumber = Int(linkReferenceModel.linkNumber)
                        } else if !name.isEmpty {
                            let key = LegacyLinkKey(source: source, destination: destination)
                            linkNumber = nextLegacyOccurrence[key, default: 0]
                            nextLegacyOccurrence[key, default: 0] += 1
                        } else {
                            linkNumber = nil
                        }

                        results.append(LinkRegisterModel(
                            id: linkReferenceModel.uuid ?? UUID(),
                            name: name,
                            source: source,
                            destination: destination,
                            linkNumber: linkNumber,
                            command: linkReferenceModel.command
                        ))
                    }
                    return results
                } catch {
                    Logger.coreDataController.error("tagdata error \(error.localizedDescription, privacy: .public)")
                    return []
                }
            }

            // Apply the fully-parsed batch with a single MainActor hop instead of one
            // unstructured `Task` per row (the old `updateLink(addedModel:)` behavior) —
            // the per-row Tasks let `setup(context:)` return before rehydration actually
            // finished, so an edit made right after launch could run its synchronous
            // dedup check against a partially-populated register and register a
            // duplicate link. See CODE_AUDIT_EditItem §3.1.
            for parsedModel in parsedModels {
                model.append(parsedModel)
            }
        }
    }
}

public extension LinkRegisterController {
    /// Returns `true` if any registered link points to `link` as its destination (i.e. the item is referenced somewhere).
    @MainActor func isUsed(link: ItemRowModel) -> Bool {
        let keyId = link.itemId
        let used = !(model.items[keyId]?.isEmpty ?? true)
        return used
    }
    
    /// Clears in-memory links whose destination matches `item`. Call before deletion to avoid stale references.
    @MainActor func resetUsedLink(for item: ItemRowModel) {
        model.pendingAffectedSourceIds.formUnion(model.removeLinks(to: item))
    }

    /// Returns all source items that link to `link` as their destination — used to populate "used by" UI.
    @MainActor func used(for link: ItemRowModel) -> [AffectedItemModel] {
        let keyId = link.itemId
        let links = model.items[keyId, default: []]
        return links.compactMap {
            guard let rootController = root?.itemRootController(for: $0.source.typeId), let item = rootController.itemControllable.itemSync(for: $0.source.itemId) else {
                return nil
            }
            var entryName: String? = nil
            if let entryId = $0.source.entryId {
                entryName = item[entryId].name
            }
            return AffectedItemModel(id: UUID(), name: item.name, entryName: entryName, module: $0.source.typeId)
        }
    }

    /// Returns outgoing links from a source entry — all items this entry references.
    @MainActor func linksFrom(source: ItemRowModel) -> [LinkRegisterModel] {
        guard source.entryId != nil else { return [] }
        return model.sourceItems[source.itemId, default: []].filter { $0.source == source }
    }
    
    /// Triggers `validateLinks` on every source module that has a registered link pointing to any of `items` — call on deletion or move.
    @MainActor func repairLinks(for items: [ItemRowModel]) {
        for item in items {
            let keyId = item.itemId
            let links = model.items[keyId, default: []]
            for link in links {
                guard let linkController = root?.itemRootController(for: link.source.typeId)?.linkControllable else { continue }
                linkController.validateLinks(on: link.source.itemId)
            }
        }
    }
}

public extension LinkRegisterController {
    /// Clears all in-memory links and deletes every persisted `LinkReferenceDataModel` row. Call from `resetData()`.
    @MainActor func resetData() async {
        model.reset()
        model.pendingAffectedSourceIds = []
        guard let context = model.context else { return }
        await context.perform {
            // Through the context, not `NSBatchDeleteRequest`: batch requests bypass the
            // CloudKit mirroring export, so the deletions never reach other devices.
            // See CODE_AUDIT_15 §5.8.
            do {
                let request: NSFetchRequest<NSFetchRequestResult> = LinkReferenceDataModel.fetchRequest()
                request.includesPropertyValues = false
                for object in try context.fetch(request) as? [NSManagedObject] ?? [] {
                    context.delete(object)
                }
                if context.hasChanges { try context.save() }
            } catch {
                context.rollbackRestoringFlushedOperations(after: error)
                Logger.coreDataController.error("link resetData error \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}

public extension LinkRegisterController {
    /// Persists all link changes accumulated since the last call. Performs a delete-and-replace per affected
    /// source item ID: delete the persisted rows, then insert the current in-memory state, through the context.
    /// Call from the periodic `save()` on `AdventureRootModel`.
    @MainActor func savePendingLinks() async throws {
        let affectedIds = model.pendingAffectedSourceIds
        guard !affectedIds.isEmpty, let context = model.context else { return }
        model.pendingAffectedSourceIds.removeAll()

        let currentLinks = model.items.values.joined().filter { affectedIds.contains($0.source.itemId) }

        // Context-based delete + insert (not `NSBatchDeleteRequest`/`NSBatchInsertRequest`):
        // `LinkReferenceDataModel` is CloudKit-mirrored and batch requests bypass the export,
        // so deletions never reached other devices and mirrored rows duplicated rebuilt ones.
        // See CODE_AUDIT_15 §5.8.
        do {
            try await context.perform {
                // Diff against the persisted rows instead of delete-and-reinsert: only changed rows
                // reach the CloudKit export and concurrent devices no longer duplicate rows.
                // See CODE_AUDIT_17 §7.7.
                let request: NSFetchRequest<NSFetchRequestResult> = LinkReferenceDataModel.fetchRequest()
                request.predicate = NSPredicate(format: "sourceId IN %@", affectedIds as NSSet)
                var existing: [UUID: LinkReferenceDataModel] = [:]
                // Keep the duplicate with the lowest object-ID URI, not whichever the unsorted
                // fetch returned first: two devices then keep the same row instead of each
                // deleting the other's. See CODE_AUDIT_18 §5.13.
                let fetched = (try context.fetch(request) as? [LinkReferenceDataModel] ?? [])
                    .sorted { $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString }
                for object in fetched {
                    if let id = object.uuid, existing[id] == nil {
                        existing[id] = object
                    } else {
                        context.delete(object)
                    }
                }
                var currentIds: Set<UUID> = []
                for link in currentLinks {
                    currentIds.insert(link.id)
                    let dbModel = existing[link.id] ?? LinkReferenceDataModel(context: context)
                    Self.assign(link, to: dbModel)
                }
                for (id, object) in existing where !currentIds.contains(id) {
                    context.delete(object)
                }
                do {
                    if context.hasChanges { try context.save() }
                } catch {
                    context.rollbackRestoringFlushedOperations(after: error)
                    throw error
                }
            }
        } catch {
            Logger.coreDataController.error("link save error \(error.localizedDescription, privacy: .public)")
            // Restore the affected-source set cleared above so the next `save()`
            // retries this batch instead of silently dropping the pending link
            // change. See CODE_AUDIT_17 §5.5.
            model.pendingAffectedSourceIds.formUnion(affectedIds)
            throw error
        }
    }
}

private extension LinkRegisterController {
    /// Writes `link` into `dbModel`, touching only properties that differ so an unchanged row
    /// stays clean and produces no CloudKit export.
    nonisolated static func assign(_ link: LinkRegisterModel, to dbModel: LinkReferenceDataModel) {
        func set<T: Equatable>(_ keyPath: ReferenceWritableKeyPath<LinkReferenceDataModel, T>, _ value: T) {
            if dbModel[keyPath: keyPath] != value { dbModel[keyPath: keyPath] = value }
        }
        set(\.uuid, link.id)
        set(\.name, link.name)
        set(\.sourceId, link.source.itemId)
        set(\.sourceEntryId, link.source.entryId)
        set(\.sourceModule, Int16(link.source.typeId.rawValue))
        set(\.destinationId, link.destination.itemId)
        set(\.destinationEntryId, link.destination.entryId)
        set(\.destinationModule, Int16(link.destination.typeId.rawValue))
        set(\.linkNumber, Int64(link.linkNumber ?? -1))
        set(\.command, link.command)
    }
}

public extension LinkRegisterController {
    /// Adds links to both in-memory indexes and marks their source items for persistence. Called on edit save and import.
    @MainActor func register(links: [LinkRegisterModel]) {
        for link in links {
            updateLinkSync(addedModel: link)
        }
    }
    
    /// Removes links from both in-memory indexes and marks their source items for persistence.
    @MainActor func deregister(links: [LinkRegisterModel]) {
        for link in links {
            updateLinkSync(removedModel: link)
        }
    }
}

private extension LinkRegisterController {
    @MainActor func updateLinkSync(addedModel: LinkRegisterModel) {
        if model.append(addedModel) {
            model.pendingAffectedSourceIds.insert(addedModel.source.itemId)
        }
    }

    @MainActor func updateLinkSync(removedModel: LinkRegisterModel) {
        if model.remove(removedModel) {
            model.pendingAffectedSourceIds.insert(removedModel.source.itemId)
        }
    }
}

// MARK: - Editor

public extension LinkRegisterController {
    /// Finds a single registered link by its UUID, scanning all destinations. Returns `nil` if not found.
    @MainActor func linkRegisterModel(linkId: UUID) -> LinkRegisterModel? {
        for (_, links) in model.items {
            if let found = links.first(where: { $0.id == linkId }) {
                return found
            }
        }
        return nil
    }

    /// Parses `text` for embedded markdown links, registers any that are new, and returns all matching `LinkRegisterModel`s for `source`.
    @MainActor func linkRegisterModel(in text: String, for source: ItemRowModel) -> [LinkRegisterModel] {
        let links = LinkReplaceController.links(for: text)
        return links.compactMap { rawLink -> LinkRegisterModel? in
            // Check if link already exists in the in-memory model
            let itemLinks = model.items[rawLink.itemId, default: []]
            if var linkRegisterModel = itemLinks.first(where: { 
                $0.source == source &&
                $0.destination.itemId == rawLink.itemId &&
                $0.destination.entryId == rawLink.entryId &&
                $0.destination.typeId == rawLink.module &&
                $0.linkNumber == rawLink.linkNumber &&
                $0.command == rawLink.command
            }) {
                linkRegisterModel.markDown = rawLink.markDown
                return linkRegisterModel
            }
            
            // Create new link and register it
            let newModel = LinkRegisterModel(
                name: rawLink.name,
                source: source,
                destination: ItemRowModel(itemId: rawLink.itemId, entryId: rawLink.entryId, typeId: rawLink.module),
                linkNumber: rawLink.linkNumber,
                command: rawLink.command,
                markDown: rawLink.markDown
            )
            register(links: [newModel])
            return newModel
        }
    }
}

private struct LegacyLinkKey: Hashable {
    let source: ItemRowModel
    let destination: ItemRowModel
}
