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
}

public struct TagController: Sendable {
    @MainActor public init() {
        self.model = TagInternalControllerModel()
    }
    
    let model: TagInternalControllerModel
    
    @MainActor public func setup(context: NSManagedObjectContext?) {
        guard let context else { return }
        model.context = context
        
        Task.detached(priority: .userInitiated) {
            await context.perform {
                do {
                    let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                    guard let tagModels = try context.fetch(request) as? [TagDataModel] else { return }
                    for tagModel in tagModels {
                        let module = NetworkModules(rawValue: Int(tagModel.module)) ?? .none
                        let tag = tagModel.title ?? String(localized: "Not set").localizedString
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
            updateDatabase(tag: tag, count: tagModel.count, module: module)
        }
        model.tags[module] = storedTags
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
            updateDatabase(tag: tag, count: tagModel.count, module: module)
        }
        model.tags[module] = storedTags
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
        tags[tag] = TagModel(module: module, title: tag, count: count)
        model.tags[module] = tags
        
        updateDatabase(tag: tag, count: count, module: module)
    }
    
    @MainActor private func updateDatabase(tag: String, count: Int, module: NetworkModules) {
        guard let context = model.context else { return }
        Task.detached(priority: .userInitiated) {
            await context.perform {
                do {
                    let request: NSFetchRequest<NSFetchRequestResult> = TagDataModel.fetchRequest()
                    request.predicate = NSPredicate(format: "module == %@ AND title == %@", NSNumber(value: module.rawValue), tag as CVarArg)
                    let tagModels = try context.fetch(request)
                    if let tagModel = tagModels.first as? TagDataModel {
                        if count > 0 {
                            tagModel.count = Int32(count)
                        } else {
                            context.delete(tagModel)
                        }
                    } else {
                        guard count > 0 else { return }
                        let tagModel = TagDataModel(context: context)
                        tagModel.module = Int16(module.rawValue)
                        tagModel.title = tag
                        tagModel.count = Int32(count)
                    }
                } catch {
                    Logger.coreDataController.error("tagdata error \(error.localizedDescription, privacy: .public)")
                }
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
