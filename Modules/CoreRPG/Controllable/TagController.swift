// @copyright André Trettin

import CoreData
import Foundation


struct TagModel: Sendable, Codable {
    var module: NetworkModules
    var title: String
    var count: Int
}

@MainActor @Observable
final class TagInternalControllerModel: @unchecked Sendable {
    @ObservationIgnored var context: NSManagedObjectContext?
    var tags: [NetworkModules: [TagModel]] = [:]
}

public struct TagController: Sendable {
    @MainActor public init() {
        self.model = TagInternalControllerModel()
    }
    
    let model: TagInternalControllerModel
    
    @MainActor public func setup(context: NSManagedObjectContext) {
        model.context = context
    }
    
    public func add(tag: String, module: NetworkModules) {
        
    }
    
    public func remove(tag: String, module: NetworkModules) {
        
    }
    
    @MainActor public func sugguestionTags(module: NetworkModules, search: String) -> [String] {
        model.tags[module, default: []]
            .filter { $0.title.localizedCaseInsensitiveContains(search) }
            .sorted { $0.count > $1.count }
            .map(\.title)
    }
    
    @MainActor public static let preview: TagController = TagController()
}
