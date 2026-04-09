// @copyright André Trettin

import CoreRPG
import WidgetKit

// MARK: - Dice Configuration

public struct DiceConfiguration: Codable {
    public init(selectedDice: DiceModel, lastRoll: DiceResultModel? = nil, availableDice: [DieModel], showHistory: Bool) {
        self.selectedDice = selectedDice
        self.lastRoll = lastRoll
        self.availableDice = availableDice
        self.showHistory = showHistory
    }
    
    public var selectedDice: DiceModel
    public var lastRoll: DiceResultModel?
    public var availableDice: [DieModel]
    public var showHistory: Bool
    
    public static var `default`: DiceConfiguration {
        DiceConfiguration(
            selectedDice: DiceModel.preview,
            lastRoll: nil,
            availableDice: [.die4(color: .G), .die6(color: .G), .die8(color: .G), .die10(color: .G), .die12(color: .G), .die20(color: .G)],
            showHistory: true
        )
    }
    
    public static func loadFromUserDefaults() -> DiceConfiguration {
        guard let data = UserDefaults(suiteName: UserDefaults.appGroupString)?.data(forKey: "diceConfiguration"),
              let config = try? JSONDecoder().decode(DiceConfiguration.self, from: data) else {
            return .default
        }
        return config
    }
    
    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults(suiteName: UserDefaults.appGroupString)?.set(data, forKey: "diceConfiguration")
        }
    }
}
