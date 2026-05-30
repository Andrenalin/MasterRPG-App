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
final class TagInternalControllerModel: @unchecked Sendable {
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
        
        Task(priority: .userInitiated) {
            await context.perform {
                do {
                    let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                    guard let tagModels = try context.fetch(request) as? [TagDataModel] else { return }
                    for tagModel in tagModels {
                        let module = NetworkModules(rawValue: Int(tagModel.module)) ?? .none
                        let tag = tagModel.title ?? String(localized: "Not set", bundle: .module).localizedString
                        let count = Int(tagModel.count)
                        update(tag: tag, count: count, module: module)
                    }
                } catch {
                    Logger.coreDataController.error("tagdata error \(error.localizedDescription, privacy: .public)")
                }
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
    
    private func update(tag: String, count: Int, module: NetworkModules) {
        Task { @MainActor in
            var tags = model.tags[module, default: [:]]
            tags[tag] = TagModel(module: module, title: tag, count: count)
            model.tags[module] = tags
        }
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
            do {
                let deleteRequest: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                try context.execute(NSBatchDeleteRequest(fetchRequest: deleteRequest))
            } catch {
                Logger.coreDataController.error("tag resetData error \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    /// Persists all tag changes accumulated since the last call. Performs a delete-and-replace per affected
    /// module: one `NSBatchDeleteRequest` then one `NSBatchInsertRequest` using the current in-memory state.
    /// Call from the periodic `save()` on `AdventureRootModel`.
    @MainActor public func savePendingTags() async {
        let affectedModules = model.pendingAffectedModules
        guard !affectedModules.isEmpty, let context = model.context else { return }
        model.pendingAffectedModules = []

        let currentTags = affectedModules.flatMap { model.tags[$0, default: [:]].values }
        let moduleRawValues = affectedModules.map { NSNumber(value: $0.rawValue) }

        await context.perform {
            do {
                let deleteRequest: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                deleteRequest.predicate = NSPredicate(format: "module IN %@", moduleRawValues as NSArray)
                try context.execute(NSBatchDeleteRequest(fetchRequest: deleteRequest))

                var iter = currentTags.makeIterator()
                let batchInsert = NSBatchInsertRequest(
                    entity: TagDataModel.entity()
                ) { (object: NSManagedObject) -> Bool in
                    guard let tag = iter.next(), let dbModel = object as? TagDataModel else { return true }
                    dbModel.module = Int16(tag.module.rawValue)
                    dbModel.title = tag.title
                    dbModel.count = Int32(tag.count)
                    return false
                }
                try context.execute(batchInsert)
            } catch {
                Logger.coreDataController.error("tag save error \(error.localizedDescription, privacy: .public)")
            }
        }
    }
    
    @MainActor public func sugguestionTags(module: NetworkModules, search: String) -> [String] {
        model.tags[module, default: [:]]
            .filter { $0.value.title.localizedCaseInsensitiveContains(search) }
            .sorted { $0.value.count > $1.value.count }
            .map(\.value.title)
    }
    
    @MainActor public static let preview: TagController = TagController()
}
