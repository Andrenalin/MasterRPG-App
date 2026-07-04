// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import WidgetKit

// MARK: - Favorite Dice Item

/// Represents a favorite dice configuration with a custom name
public struct FavoriteDiceItem: Codable, Identifiable, Equatable {
    public let id: UUID
    public var name: String
    public var diceModel: DiceSnapshot
    
    public init(id: UUID = UUID(), name: String, diceModel: DiceSnapshot) {
        self.id = id
        self.name = name
        self.diceModel = diceModel
    }
}

// MARK: - Dice Configuration

public struct DiceConfiguration: Codable {
    public init(selectedDice: DiceSnapshot, lastRoll: DiceResultModel? = nil, availableDice: [DieModel], showHistory: Bool, favoriteDice: [FavoriteDiceItem] = []) {
        self.selectedDice = selectedDice
        self.lastRoll = lastRoll
        self.availableDice = availableDice
        self.showHistory = showHistory
        self.favoriteDice = favoriteDice
    }
    
    public var selectedDice: DiceSnapshot
    public var lastRoll: DiceResultModel?
    public var availableDice: [DieModel]
    public var showHistory: Bool
    public var favoriteDice: [FavoriteDiceItem]
    
    public static var `default`: DiceConfiguration {
        DiceConfiguration(
            selectedDice: DiceModel.previewSnapshot,
            lastRoll: nil,
            availableDice: [.die4(color: .G), .die6(color: .G), .die8(color: .G), .die10(color: .G), .die12(color: .G), .die20(color: .G)],
            showHistory: true,
            favoriteDice: []
        )
    }
    
    public static func loadFromUserDefaults() -> DiceConfiguration {
        guard let data = UserDefaults(suiteName: UserDefaults.appGroupString)?.data(forKey: UserDefaults.DiceKeys.diceConfiguration),
              let config = try? JSONDecoder().decode(DiceConfiguration.self, from: data) else {
            return .default
        }
        return config
    }
    
    public func save() {
        if let data = try? JSONEncoder().encode(self) {
            UserDefaults(suiteName: UserDefaults.appGroupString)?.set(data, forKey: UserDefaults.DiceKeys.diceConfiguration)
        }
    }
}

#endif
