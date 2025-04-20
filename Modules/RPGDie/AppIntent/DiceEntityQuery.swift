// @copyright André Trettin

import AppIntents

//public struct DiceWidgetIntentEntity: AppEntity {
//    public init(id: String, itemId: UUID) {
//        self.id = id
//        self.itemId = itemId
//    }
//    
//    public var id: String
//    public var itemId: UUID
//    
//    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Selected Dice")
//    
//    public var displayRepresentation: DisplayRepresentation {
//        DisplayRepresentation(title: "\(id)")
//    }
//    
//    public static let defaultQuery = DiceEntityQuery()
//}
//
//
//public struct DiceEntityQuery: EntityQuery {
//    public init() {}
//    
//    public func entities(for identifiers: [String]) async throws -> [DiceWidgetIntentEntity] {
//        try await suggestedEntities().filter { identifiers.contains($0.id) }
//    }
//    
//    @MainActor public func suggestedEntities() async throws -> [DiceWidgetIntentEntity] {
//        guard let root = DiceFactory.sharedRoot else { return [] }
//        var results: [DiceWidgetIntentEntity] = []
//        for itemId in root.itemController.itemDataModel.items {
//            let name = root.itemController.nameSync(itemId: itemId)
//            let entity = DiceWidgetIntentEntity(id: name, itemId: itemId)
//            results.append(entity)
//        }
//        return results
//    }
//}

//struct DiceEntityQuery: EntityQuery {
//    func entities(for identifiers: [String]) async throws -> [DiceWidgetIntentEntity] {
//        try await suggestedEntities().filter { identifiers.contains($0.id) }
//    }
//    
//    @MainActor func suggestedEntities() async throws -> [DiceWidgetIntentEntity] {
//        let root = DataBaseLoader.shared.appStore.diceRoot
//        var results: [DiceWidgetIntentEntity] = []
//        for itemId in root.itemControllable.itemDataModel.items {
//            let name = root.itemControllable.nameSync(itemId: itemId)
//            let entity = DiceWidgetIntentEntity(id: itemId.uuidString)
//            results.append(entity)
//        }
//        return results
//    }
//}
