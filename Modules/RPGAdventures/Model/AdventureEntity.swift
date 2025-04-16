// @copyright André Trettin

import AndrenalinKit
import AppIntents
import Foundation
import SwiftUI

public struct AdventureEntity: AppEntity {
    @Property(title: "Adventure Name")
    public var name: String
    
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = "Adventure"
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(stringLiteral: name)
//        DisplayRepresentation(title: name, subtitle: nil, image: Image(systemName: "gear"))
        //DisplayRepresentation(title: name, subtitle: nil, image: Image(systemName: NetworkModules.adventure.icon))
    }
    
    public var id: UUID
    
    public static let defaultQuery = AdventureEntityQuery()
}

extension AdventureEntity {
    init(adventure: AdventureModel) {
        self.id = adventure.id
        self.name = adventure.name
    }
}


public struct AdventureEntityQuery: EntityQuery {
    public init() {}
    
    public func entities(for identifiers: [UUID]) async throws -> [AdventureEntity] {
        guard let itemController = await AdventureFactory.sharedRoot?.itemController else { return [] }
        var results: [AdventureEntity] = []
        for itemId in identifiers {
            guard let adventureModel = await itemController.itemSync(for: itemId) else { continue }
            let entity = AdventureEntity(adventure: adventureModel)
            results.append(entity)
        }
        return results
    }
}

extension AdventureEntityQuery: EnumerableEntityQuery {
    public func allEntities() async throws -> [AdventureEntity] {
        guard let itemController = await AdventureFactory.sharedRoot?.itemController else { return [] }
        var results: [AdventureEntity] = []
        for itemId in await itemController.itemDataModel.items {
            guard let adventureModel = await itemController.itemSync(for: itemId) else { continue }
            let entity = AdventureEntity(adventure: adventureModel)
            results.append(entity)
        }
        return results
    }
}
