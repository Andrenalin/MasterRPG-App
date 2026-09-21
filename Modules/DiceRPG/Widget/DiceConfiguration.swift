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

// `DiceWidgetSnapshot` and `DiceConfiguration` each hand-rolled an identical
// encode/decode + App-Group-UserDefaults read/write pair. See CODE_AUDIT §9.18.
private enum AppGroupCodableStore {
    static func load<T: Codable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.appGroupDefaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }

    static func save<T: Codable>(_ value: T, key: String) {
        guard let data = try? JSONEncoder().encode(value) else { return }
        UserDefaults.appGroupDefaults?.set(data, forKey: key)
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

public struct DiceWidgetSnapshot: Codable, Equatable, Sendable {
    public init(
        selectedDice: DiceWidgetDice,
        lastRoll: DiceWidgetRoll? = nil,
        showHistory: Bool = true
    ) {
        self.selectedDice = selectedDice
        self.lastRoll = lastRoll
        self.showHistory = showHistory
    }

    public init(configuration: DiceConfiguration) {
        self.init(
            selectedDice: DiceWidgetDice(configuration.selectedDice),
            lastRoll: configuration.lastRoll.map(DiceWidgetRoll.init),
            showHistory: configuration.showHistory
        )
    }

    public var selectedDice: DiceWidgetDice
    public var lastRoll: DiceWidgetRoll?
    public var showHistory: Bool

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
            showHistory: true
        )
    }

    public static func loadFromUserDefaults() -> DiceWidgetSnapshot {
        if let snapshot = AppGroupCodableStore.load(DiceWidgetSnapshot.self, key: UserDefaults.DiceKeys.widgetSnapshot) {
            return snapshot
        }

        let snapshot = DiceWidgetSnapshot(configuration: DiceConfiguration.loadFromUserDefaults())
        snapshot.save()
        return snapshot
    }

    public func save() {
        AppGroupCodableStore.save(self, key: UserDefaults.DiceKeys.widgetSnapshot)
    }
}

// MARK: - Dice Configuration

public struct DiceConfiguration: Codable {
    // `availableDice` was previously stored and re-encoded to the App Group
    // on every roll but never read back anywhere — dead field, dropped along
    // with the write it cost each roll. See CODE_AUDIT §7.1.
    public init(selectedDice: DiceSnapshot, lastRoll: DiceResultModel? = nil, showHistory: Bool) {
        self.selectedDice = selectedDice
        self.lastRoll = lastRoll
        self.showHistory = showHistory
    }

    public var selectedDice: DiceSnapshot
    public var lastRoll: DiceResultModel?
    public var showHistory: Bool

    public static var `default`: DiceConfiguration {
        DiceConfiguration(
            selectedDice: DiceModel.previewSnapshot,
            lastRoll: nil,
            showHistory: true
        )
    }
    
    public static func loadFromUserDefaults() -> DiceConfiguration {
        AppGroupCodableStore.load(DiceConfiguration.self, key: UserDefaults.DiceKeys.diceConfiguration) ?? .default
    }

    public func save() {
        AppGroupCodableStore.save(self, key: UserDefaults.DiceKeys.diceConfiguration)
        DiceWidgetSnapshot(configuration: self).save()
    }
}

#endif
