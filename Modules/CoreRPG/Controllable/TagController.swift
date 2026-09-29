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
}

public struct TagController: Sendable {
    @MainActor public init() {
        self.model = TagInternalControllerModel()
    }
    
    let model: TagInternalControllerModel
    
    @MainActor public func setup(context: NSManagedObjectContext?) {
        guard let context else { return }
        model.context = context
        let missingTagTitle = String(localized: "Not set", bundle: .module).localizedString
        
        Task(priority: .userInitiated) { [model] in
            let groupedTags = await context.perform {
                do {
                    let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                    // Grows with every tagged item/entry in every module; batch the fetch
                    // instead of materializing the whole table at once.
                    request.fetchBatchSize = 500
                    guard let tagModels = try context.fetch(request) as? [TagDataModel] else { return [NetworkModules: [String: TagModel]]() }
                    return tagModels.reduce(into: [NetworkModules: [String: TagModel]]()) { result, tagModel in
                        let module = NetworkModules(rawValue: Int(tagModel.module)) ?? .none
                        let tag = tagModel.title ?? missingTagTitle
                        result[module, default: [:]][tag] = TagModel(module: module, title: tag, count: Int(tagModel.count))
                    }
                } catch {
                    Logger.coreDataController.error("tagdata error \(error.localizedDescription, privacy: .public)")
                    return [:]
                }
            }

            // Already back on the Main Actor here: this `Task` literal was created
            // directly inside `setup(context:)`'s @MainActor body, so it inherits that
            // isolation, and `await context.perform` only hops off-actor for the
            // duration of the Core Data fetch above.
            for (module, tags) in groupedTags {
                model.tags[module, default: [:]].merge(tags) { _, new in new }
            }
        }
    }

    @MainActor public func add(tags: [String], module: NetworkModules) {
        var storedTags = model.tags[module, default: [:]]
        for tag in tags {
            var tagModel = storedTags[tag, default: TagModel(module: module, title: tag, count: 0)]
            tagModel.count += 1
            storedTags[tag] = tagModel
        }
        model.tags[module] = storedTags
        model.pendingAffectedModules.insert(module)
    }

    @MainActor public func remove(tags: [String], module: NetworkModules) {
        var storedTags = model.tags[module, default: [:]]
        for tag in tags {
            guard var tagModel = storedTags[tag] else { continue }
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
        model.tags = [:]
        model.pendingAffectedModules = []
        guard let context = model.context else { return }
        await context.perform {
            // Through the context, not `NSBatchDeleteRequest` (bypasses CloudKit mirroring).
            // See CODE_AUDIT_15 §5.8.
            do {
                let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                request.includesPropertyValues = false
                for object in try context.fetch(request) as? [NSManagedObject] ?? [] {
                    context.delete(object)
                }
                if context.hasChanges { try context.save() }
            } catch {
                context.rollbackRestoringFlushedOperations(after: error)
                Logger.coreDataController.error("tag resetData error \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Persists all tag changes accumulated since the last call. Performs a delete-and-replace per affected
    /// module: delete the persisted rows, then insert the current in-memory state, through the context.
    /// Call from the periodic `save()` on `AdventureRootModel`.
    @MainActor public func savePendingTags() async throws {
        let affectedModules = model.pendingAffectedModules
        guard !affectedModules.isEmpty, let context = model.context else { return }
        model.pendingAffectedModules = []

        let currentTags = affectedModules.flatMap { model.tags[$0, default: [:]].values }
        let moduleRawValues = affectedModules.map { NSNumber(value: $0.rawValue) }

        // Context-based delete + insert: `TagDataModel` is CloudKit-mirrored and batch requests
        // bypass the export. See CODE_AUDIT_15 §5.8.
        do {
            try await context.perform {
                // Upsert by (module, title) instead of delete-and-reinsert: only changed rows reach
                // the CloudKit export. See CODE_AUDIT_17 §7.7.
                let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                request.predicate = NSPredicate(format: "module IN %@", moduleRawValues as NSArray)
                var existing: [String: TagDataModel] = [:]
                // Deterministic survivor (lowest object-ID URI) so two devices keep the same
                // duplicate. See CODE_AUDIT_18 §5.13.
                let fetched = (try context.fetch(request) as? [TagDataModel] ?? [])
                    .sorted { $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString }
                for object in fetched {
                    let key = "\(object.module)|\(object.title ?? "")"
                    if existing[key] == nil {
                        existing[key] = object
                    } else {
                        context.delete(object)
                    }
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
                    if context.hasChanges { try context.save() }
                } catch {
                    context.rollbackRestoringFlushedOperations(after: error)
                    throw error
                }
            }
        } catch {
            Logger.coreDataController.error("tag save error \(error.localizedDescription, privacy: .public)")
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
