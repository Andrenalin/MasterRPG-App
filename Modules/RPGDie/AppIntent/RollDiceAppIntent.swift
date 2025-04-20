// @copyright André Trettin

import AppIntents

public struct RollDiceAppIntent: AppIntent {
    public static let title: LocalizedStringResource = "Roll a dice"
    public static let description: IntentDescription? = IntentDescription("Tap the dice to roll")
    
    @Parameter(title: "Dice")
    var name: String
    
    public init(name: String) {
        self.name = name
    }
    
    public init() {
        name = ""
    }

    public func perform() async throws -> some IntentResult {
        let update = await updateDice(name: name)
        return .result(value: update)
    }
    
    @MainActor public func updateDice(name: String) -> Int {
        return Int.random(in: 1...20)
    }
}
