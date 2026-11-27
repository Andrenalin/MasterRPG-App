// @copyright André Trettin

import CoreData
import Foundation
import os.log

struct TagModel: Sendable, Codable {
    var module: NetworkModules
    var title: String
    var count: Int
}

@MainActor @Observable
final class TagInternalControllerModel {
    @ObservationIgnored var context: NSManagedObjectContext?

    var tags: [NetworkModules: [String: TagModel]] = [:]
    var pendingAffectedModules: Set<NetworkModules> = []

    /// Whether the persisted tag table has been merged into `tags`. A save before that would read an
    /// incomplete table as "everything else is stale" and delete the persisted rows.
    /// See CODE_AUDIT_26 §5.9.
    @ObservationIgnored var isHydrated = false
    /// The last hydration fetch failed; the next save retries it and is skipped while it keeps failing.
    @ObservationIgnored var hydrationFailed = false
    @ObservationIgnored var hydrationTask: Task<Bool, Never>?
    /// Replaces the store fetch (tests inject a failing one). Returns nil on failure.
    @ObservationIgnored var persistedFetchOverride: (@Sendable (NSManagedObjectContext) async -> [NetworkModules: [String: TagModel]]?)?
    /// Count changes made in memory before hydration finished, so the persisted baseline can be added.
    @ObservationIgnored var unhydratedDeltas: [NetworkModules: [String: Int]] = [:]
    /// Tags set to an absolute count before hydration finished; the persisted count does not apply.
    @ObservationIgnored var unhydratedAbsolute: [NetworkModules: Set<String>] = [:]
}

public struct TagController: Sendable {
    @MainActor public init() {
        self.model = TagInternalControllerModel()
    }
    
    let model: TagInternalControllerModel
    
    @MainActor public func setup(context: NSManagedObjectContext?) {
        guard let context else { return }
        model.context = context
        hydrate()
    }

    /// Fetches the persisted tags and merges them into memory. One run at a time; callers wait on
    /// the returned task. Returns whether the fetch succeeded.
    @MainActor @discardableResult
    private func hydrate() -> Task<Bool, Never> {
        if let running = model.hydrationTask { return running }
        guard let context = model.context else { return Task { false } }
        let missingTagTitle = String(localized: "Not set", bundle: .module)
        // The Task literal inherits this method's main-actor isolation; only the Core Data fetch
        // hops off-actor inside `context.perform`.
        let task = Task(priority: .userInitiated) { [model] in
            let fetched: [NetworkModules: [String: TagModel]]?
            if let override = model.persistedFetchOverride {
                fetched = await override(context)
            } else {
                fetched = await Self.fetchPersistedTags(context: context, missingTagTitle: missingTagTitle)
            }
            model.hydrationTask = nil
            guard let persisted = fetched else {
                model.hydrationFailed = true
                return false
            }
            Self.apply(persisted: persisted, to: model)
            model.isHydrated = true
            model.hydrationFailed = false
            model.unhydratedDeltas = [:]
            model.unhydratedAbsolute = [:]
            return true
        }
        model.hydrationTask = task
        return task
    }

    /// `nil` when the fetch failed (as opposed to an empty table).
    private static func fetchPersistedTags(context: NSManagedObjectContext, missingTagTitle: String) async -> [NetworkModules: [String: TagModel]]? {
        await context.perform {
            do {
                let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                // Grows with every tagged item/entry in every module; batch the fetch
                // instead of materializing the whole table at once.
                request.fetchBatchSize = CoreDataFetchLimits.batchSize
                guard let tagModels = try context.fetch(request) as? [TagDataModel] else {
                    Logger.coreDataController.error("tagdata error: unexpected fetch result type")
                    return nil
                }
                return tagModels.reduce(into: [NetworkModules: [String: TagModel]]()) { result, tagModel in
                    let module = NetworkModules(rawValue: Int(tagModel.module)) ?? .none
                    let tag = tagModel.title ?? missingTagTitle
                    result[module, default: [:]][tag] = TagModel(module: module, title: tag, count: Int(tagModel.count))
                }
            } catch {
                Logger.coreDataController.error("tagdata error \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
                return nil
            }
        }
    }

    @MainActor private static func apply(persisted: [NetworkModules: [String: TagModel]], to model: TagInternalControllerModel) {
        for (module, tags) in persisted {
            model.tags[module] = merged(
                memory: model.tags[module, default: [:]],
                persisted: tags,
                deltas: model.unhydratedDeltas[module, default: [:]],
                absolute: model.unhydratedAbsolute[module, default: []]
            )
        }
    }

    /// Merges the persisted tags of one module into the in-memory ones. A tag nobody touched before
    /// the fetch finished takes the persisted count; a tag changed by `add`/`remove` gets the
    /// persisted count plus the change; a tag set to an absolute count keeps it.
    static func merged(memory: [String: TagModel], persisted: [String: TagModel], deltas: [String: Int], absolute: Set<String>) -> [String: TagModel] {
        var result = memory
        for (title, tag) in persisted where !absolute.contains(title) {
            var tag = tag
            if let delta = deltas[title] {
                tag.count = max(0, tag.count + delta)
            }
            result[title] = tag.count > 0 ? tag : nil
        }
        return result
    }

    @MainActor public func add(tags: [String], module: NetworkModules) {
        var storedTags = model.tags[module, default: [:]]
        for tag in tags {
            var tagModel = storedTags[tag, default: TagModel(module: module, title: tag, count: 0)]
            tagModel.count += 1
            storedTags[tag] = tagModel
            trackDelta(1, tag: tag, module: module)
        }
        model.tags[module] = storedTags
        model.pendingAffectedModules.insert(module)
    }

    @MainActor private func trackDelta(_ delta: Int, tag: String, module: NetworkModules) {
        guard !model.isHydrated else { return }
        model.unhydratedDeltas[module, default: [:]][tag, default: 0] += delta
    }

    @MainActor public func remove(tags: [String], module: NetworkModules) {
        var storedTags = model.tags[module, default: [:]]
        for tag in tags {
            guard var tagModel = storedTags[tag] else {
                trackDelta(-1, tag: tag, module: module)
                continue
            }
            trackDelta(-1, tag: tag, module: module)
            tagModel.count -= 1
            if tagModel.count > 0 {
                storedTags[tag] = tagModel
            } else {
                storedTags[tag] = nil
            }
        }
        model.tags[module] = storedTags
        model.pendingAffectedModules.insert(module)
    }
    
    @MainActor public func reset(tag: String, count: Int, module: NetworkModules) {
        var tags = model.tags[module, default: [:]]
        if !model.isHydrated {
            model.unhydratedAbsolute[module, default: []].insert(tag)
        }
        if count > 0 {
            tags[tag] = TagModel(module: module, title: tag, count: count)
        } else {
            tags[tag] = nil
        }
        model.tags[module] = tags
        model.pendingAffectedModules.insert(module)
    }

    /// Clears all in-memory tags and deletes every persisted `TagDataModel` row. Call from `resetData()`.
    @MainActor public func resetData() async {
        // A hydration still running would merge the rows being deleted back into memory.
        _ = await model.hydrationTask?.value
        model.tags = [:]
        model.pendingAffectedModules = []
        model.unhydratedDeltas = [:]
        model.unhydratedAbsolute = [:]
        guard let context = model.context else { return }
        // Memory and store are both empty after this, so there is nothing left to hydrate.
        model.isHydrated = true
        model.hydrationFailed = false
        await context.perform {
            // Through the context, not `NSBatchDeleteRequest` (bypasses CloudKit mirroring).
            // See CODE_AUDIT_15 §5.8.
            do {
                let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                request.includesPropertyValues = false
                for object in try context.fetch(request) as? [NSManagedObject] ?? [] {
                    context.delete(object)
                }
                if context.hasChanges {
#if DEBUG
                    context.logPendingSave("tags")
#endif
                    try context.save()
                }
            } catch {
                context.rollbackRestoringFlushedOperations(after: error)
                Logger.coreDataController.error("tag resetData error \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            }
        }
    }

    /// Persists all tag changes accumulated since the last call. Performs a delete-and-replace per affected
    /// module: delete the persisted rows, then insert the current in-memory state, through the context.
    /// Call from the periodic `save()` on `AdventureRootModel`.
    @MainActor public func savePendingTags() async throws {
        guard !model.pendingAffectedModules.isEmpty, let context = model.context else { return }
        // The in-memory table must hold the persisted rows before it can replace them; a failing
        // fetch retries here and, while it keeps failing, leaves the persisted rows and the
        // pending changes alone. See CODE_AUDIT_26 §5.9.
        if !model.isHydrated {
            guard await hydrate().value else {
                Logger.coreDataController.warning("tag save skipped: the persisted tags could not be loaded yet")
                return
            }
        }
        let affectedModules = model.pendingAffectedModules
        guard !affectedModules.isEmpty else { return }
        model.pendingAffectedModules = []

        let currentTags = affectedModules.flatMap { model.tags[$0, default: [:]].values }
        let moduleRawValues = affectedModules.map { NSNumber(value: $0.rawValue) }

        // Context-based delete + insert: `TagDataModel` is CloudKit-mirrored and batch requests
        // bypass the export. See CODE_AUDIT_15 §5.8.
        do {
            // Duplicate rows are sorted by CloudKit record names, which are looked up off the
            // context's thread (a utility-priority wait that must not block it). A pass that meets
            // duplicates whose names are not known yet changes nothing and asks for them.
            var recordNames: DuplicateRowOrder.RecordNames?
            var attempts = 0
            while true {
                attempts += 1
                let names = recordNames
                let useBlockingLookup = attempts > DuplicateRowOrder.maxLookupAttempts
                let unknownRows: [NSManagedObjectID] = try await context.perform {
                    // Upsert by (module, title) instead of delete-and-reinsert: only changed rows reach
                    // the CloudKit export. See CODE_AUDIT_17 §7.7.
                    let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                    request.predicate = NSPredicate(format: "module IN %@", moduleRawValues as NSArray)
                    var existing: [String: TagDataModel] = [:]
                    // The survivor every device keeps (`DuplicateRowOrder`); the lowest object-ID
                    // URI differs per device. See CODE_AUDIT_18 §5.13, CODE_AUDIT_21 §5.7.
                    let fetched = try context.fetch(request) as? [TagDataModel] ?? []
                    var rowsByKey: [String: [TagDataModel]] = [:]
                    for object in fetched {
                        rowsByKey["\(object.module)|\(object.title ?? "")", default: []].append(object)
                    }
                    let duplicateRows = rowsByKey.values.filter { $0.count > 1 }.flatMap { $0 }
                    if !useBlockingLookup, !duplicateRows.isEmpty, !(names?.covers(duplicateRows) ?? false) {
                        return duplicateRows.map(\.objectID)
                    }
                    for (key, rows) in rowsByKey {
                        let ordered = names.map { DuplicateRowOrder.sorted(rows, using: $0) } ?? DuplicateRowOrder.sorted(rows)
                        existing[key] = ordered.first
                        ordered.dropFirst().forEach(context.delete)
                    }
                    var currentKeys: Set<String> = []
                    for tag in currentTags {
                        let key = "\(Int16(tag.module.rawValue))|\(tag.title)"
                        currentKeys.insert(key)
                        let dbModel = existing[key] ?? TagDataModel(context: context)
                        if dbModel.module != Int16(tag.module.rawValue) { dbModel.module = Int16(tag.module.rawValue) }
                        if dbModel.title != tag.title { dbModel.title = tag.title }
                        if dbModel.count != Int32(tag.count) { dbModel.count = Int32(tag.count) }
                    }
                    for (key, object) in existing where !currentKeys.contains(key) {
                        context.delete(object)
                    }
                    do {
                        if context.hasChanges {
#if DEBUG
                            context.logPendingSave("tags")
#endif
                            try context.save()
                        }
                    } catch {
                        context.rollbackRestoringFlushedOperations(after: error)
                        throw error
                    }
                    return []
                }
                if unknownRows.isEmpty { break }
                recordNames = await DuplicateRowOrder.recordNames(for: unknownRows)
            }
        } catch {
            Logger.coreDataController.error("tag save error \(error.logIdentifier, privacy: .public) \(error.localizedDescription, privacy: .private)")
            // Restore the affected-module set cleared above so the next `save()`
            // retries this batch instead of silently dropping the pending tag
            // change. See CODE_AUDIT_17 §5.5.
            model.pendingAffectedModules.formUnion(affectedModules)
            throw error
        }
    }

    @MainActor public func suggestionTags(module: NetworkModules, search: String) -> [String] {
        model.tags[module, default: [:]]
            .filter { $0.value.title.localizedStandardContains(search) }
            .sorted { $0.value.count > $1.value.count }
            .map(\.value.title)
    }
    
    @MainActor public static let preview: TagController = TagController()
}
