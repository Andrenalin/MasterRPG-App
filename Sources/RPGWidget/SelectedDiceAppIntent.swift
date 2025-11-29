// @copyright André Trettin

import AppIntents
import DiceRPG
import WidgetKit
import CoreRPG

struct SelectedDiceAppIntent: WidgetConfigurationIntent {
    static var title: LocalizedStringResource { "Selected Dice" }
    static var description: IntentDescription { "Choose your dice from the list" }

    // An example configurable parameter.
    @Parameter(title: "Selected Dice", default: nil)
    var selectedDice: DiceWidgetIntentEntity?
}


public struct DiceWidgetIntentEntity: AppEntity {
//    public init(id: String, itemId: UUID) {
//        self.id = id
//        self.itemId = itemId
//    }
    
    public var id: String
    //public var itemId: UUID
    
    public static let typeDisplayRepresentation: TypeDisplayRepresentation = TypeDisplayRepresentation(name: "Selected Dice")
    
    public var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(id)")
    }
    
    public static let defaultQuery = DiceEntityQuery()
}


public struct DiceEntityQuery: EntityQuery {
    public init() {}
    
    public func entities(for identifiers: [String]) async throws -> [DiceWidgetIntentEntity] {
        try await suggestedEntities().filter { identifiers.contains($0.id) }
    }
    
    @MainActor public func suggestedEntities() async throws -> [DiceWidgetIntentEntity] {
        let dbLoader = DataBaseLoader.shared
        await dbLoader.setup()
        guard let root = dbLoader.diceRoot else { return [DiceWidgetIntentEntity(id: "101")] }
        var results: [DiceWidgetIntentEntity] = []
        for itemId in root.itemControllable.itemDataModel.items {
            let name = root.itemControllable.nameSync(itemId: itemId)
            let entity = DiceWidgetIntentEntity(id: itemId.uuidString) //, itemId: itemId)
            results.append(entity)
        }
        return results
    }
}
