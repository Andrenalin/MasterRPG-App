// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import WidgetKit

// MARK: - Widget Constants

public enum DiceWidgetKind {
    public static let roller = "DiceRollerWidget"
    public static let accessory = "DiceAccessory"
    public static let control = "DiceControl"
}

public enum DiceWidgetDeepLink {
    public static var diceRoot: URL? {
        URL(string: "\(URL.appScheme)://\(NetworkModules.dice.token)")
    }
}

public enum DiceWidgetReloader {
    public static func reloadDiceWidgets() {
        WidgetCenter.shared.reloadTimelines(ofKind: DiceWidgetKind.roller)
        WidgetCenter.shared.reloadTimelines(ofKind: DiceWidgetKind.accessory)
    }
}

// MARK: - Compact Widget Snapshot

public struct DiceWidgetDice: Codable, Identifiable, Equatable, Hashable, Sendable {
    public init(id: UUID, name: String, sides: Int, face: Int? = nil) {
        self.id = id
        self.name = name
        self.sides = sides
        self.face = face
    }

    public init(_ diceSnapshot: DiceSnapshot) {
        let firstDie = diceSnapshot.dice.first
        let sides = firstDie?.die.max ?? 20
        self.init(
            id: diceSnapshot.id,
            name: diceSnapshot.name.isEmpty ? "D\(sides)" : diceSnapshot.name,
            sides: sides,
            face: firstDie?.result.last
        )
    }

    public let id: UUID
    public var name: String
    public var sides: Int
    public var face: Int?

    public var displayFace: Int {
        face ?? sides
    }

    public var dieModel: DieModel {
        switch sides {
        case 4:
            .die4(color: .G)
        case 6:
            .die6(color: .G)
        case 8:
            .die8(color: .G)
        case 10:
            .die10(color: .G)
        case 12:
            .die12(color: .G)
        case 20:
            .die20(color: .G)
        default:
            DieModel(id: id, die: RawDie(.number(sides)), color: DieModel.ColorCode.G.rawValue)
        }
    }
}

public struct DiceWidgetRoll: Codable, Identifiable, Equatable, Hashable, Sendable {
    public init(
        id: UUID = UUID(),
        dice: DiceWidgetDice,
        result: DiceResultModel.DiceResult,
        values: String,
        sum: Int,
        checked: Bool,
        timestamp: Date?
    ) {
        self.id = id
        self.dice = dice
        self.result = result
        self.values = values
        self.sum = sum
        self.checked = checked
        self.timestamp = timestamp
    }

    public init(_ diceResult: DiceResultModel) {
        self.init(
            id: diceResult.id,
            dice: DiceWidgetDice(diceResult.diceModel),
            result: diceResult.result,
            values: diceResult.values,
            sum: diceResult.sum,
            checked: diceResult.checked,
            timestamp: diceResult.timestamp
        )
    }

    public let id: UUID
    public var dice: DiceWidgetDice
    public var result: DiceResultModel.DiceResult
    public var values: String
    public var sum: Int
    public var checked: Bool
    public var timestamp: Date?
}

public struct DiceWidgetFavorite: Codable, Identifiable, Equatable, Hashable, Sendable {
    public init(id: UUID, name: String, dice: DiceWidgetDice) {
        self.id = id
        self.name = name
        self.dice = dice
    }

    public init(_ favorite: FavoriteDiceItem) {
        self.init(
            id: favorite.diceModel.id,
            name: favorite.name,
            dice: DiceWidgetDice(favorite.diceModel)
        )
    }

    public let id: UUID
    public var name: String
    public var dice: DiceWidgetDice
}

public struct DiceWidgetSnapshot: Codable, Equatable, Sendable {
    public init(
        selectedDice: DiceWidgetDice,
        lastRoll: DiceWidgetRoll? = nil,
        showHistory: Bool = true,
        favoriteDice: [DiceWidgetFavorite] = []
    ) {
        self.selectedDice = selectedDice
        self.lastRoll = lastRoll
        self.showHistory = showHistory
        self.favoriteDice = favoriteDice
    }

    public init(configuration: DiceConfiguration) {
        self.init(
            selectedDice: DiceWidgetDice(configuration.selectedDice),
            lastRoll: configuration.lastRoll.map(DiceWidgetRoll.init),
            showHistory: configuration.showHistory,
            favoriteDice: configuration.favoriteDice.map(DiceWidgetFavorite.init)
        )
    }

    public var selectedDice: DiceWidgetDice
    public var lastRoll: DiceWidgetRoll?
    public var showHistory: Bool
    public var favoriteDice: [DiceWidgetFavorite]

    public static var `default`: DiceWidgetSnapshot {
        DiceWidgetSnapshot(configuration: .default)
    }

    public static var preview: DiceWidgetSnapshot {
        DiceWidgetSnapshot(
            selectedDice: DiceWidgetDice(DiceModel.previewSnapshot),
            lastRoll: DiceWidgetRoll(
                DiceResultModel(
                    diceModel: DiceModel.previewSnapshot,
                    result: .rolled,
                    values: "18",
                    sum: 18,
                    checked: false
                )
            ),
            showHistory: true,
            favoriteDice: []
        )
    }

    public static func loadFromUserDefaults() -> DiceWidgetSnapshot {
        let defaults = UserDefaults(suiteName: UserDefaults.appGroupString)
        if let data = defaults?.data(forKey: UserDefaults.DiceKeys.widgetSnapshot),
           let snapshot = try? JSONDecoder().decode(DiceWidgetSnapshot.self, from: data) {
            return snapshot
        }

        let snapshot = DiceWidgetSnapshot(configuration: DiceConfiguration.loadFromUserDefaults())
        snapshot.save()
        return snapshot
    }

    public func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: UserDefaults.appGroupString)?.set(data, forKey: UserDefaults.DiceKeys.widgetSnapshot)
    }
}

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
        DiceWidgetSnapshot(configuration: self).save()
    }
}

#endif
