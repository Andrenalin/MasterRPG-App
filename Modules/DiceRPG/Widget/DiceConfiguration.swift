// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import Synchronization
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
        return try? JSONCoding.decoder.decode(T.self, from: data)
    }

    static func save<T: Codable>(_ value: T, key: String) {
        guard let data = try? JSONCoding.encoder.encode(value) else { return }
        UserDefaults.appGroupDefaults?.set(data, forKey: key)
    }
}

// MARK: - Compact Widget Snapshot

public struct DiceWidgetDice: Codable, Identifiable, Equatable, Hashable, Sendable {
    public init(id: UUID, name: String, sides: Int, face: Int? = nil, dieCount: Int? = nil) {
        self.id = id
        self.name = name
        self.sides = sides
        self.face = face
        self.dieCount = dieCount
    }

    public init(_ diceSnapshot: DiceSnapshot) {
        let firstDie = diceSnapshot.dice.first
        let sides = firstDie?.die.max ?? 20
        let count = max(diceSnapshot.dice.count, 1)
        // An unnamed multi-dice roll is named by its notation ("3D6"), not by its first die.
        let notation = count > 1 && diceSnapshot.dice.allSatisfy({ $0.die.max == sides })
            ? "\(count)D\(sides)"
            : "D\(sides)"
        self.init(
            id: diceSnapshot.id,
            name: diceSnapshot.name.isEmpty ? notation : diceSnapshot.name,
            sides: sides,
            face: firstDie?.result.last,
            dieCount: count
        )
    }

    public let id: UUID
    public var name: String
    public var sides: Int
    public var face: Int?
    /// Number of dice in the roll; `nil` for data saved before it was recorded (one die).
    public var dieCount: Int?

    /// A single die can be drawn with its face. Several dice have no one face that matches the
    /// total, so the widget shows the total as text. See CODE_AUDIT_26 §5.48.
    public var isSingleDie: Bool {
        (dieCount ?? 1) <= 1
    }

    public var displayFace: Int {
        face ?? sides
    }

    public var dieModel: DieModel {
        .die(sides: sides, id: id)
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
            selectedDice: DiceWidgetDice(DiceSnapshot.widgetDefault),
            lastRoll: DiceWidgetRoll(
                DiceResultModel(
                    diceModel: DiceSnapshot.widgetDefault,
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
            selectedDice: DiceSnapshot.widgetDefault,
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

    private static let lastRollWriteLock = Mutex<Void>(())

    /// Records `roll` as the last roll unless a newer roll is already stored. The one
    /// read-modify-write used by the app, its `RollDiceIntent` and the widget extension: the
    /// widget used to overwrite unconditionally, so a widget roll racing an app roll could
    /// replace the newer result (and the in-process lock only ever covered the app). Returns
    /// whether it wrote.
    /// Two processes can still interleave inside the tiny read-write window; the timestamp
    /// check keeps the newest roll in every other case. See CODE_AUDIT_18 §3.19.
    @discardableResult
    public static func recordLastRoll(_ roll: DiceResultModel) -> Bool {
        lastRollWriteLock.withLock { _ -> Bool in
            var config = DiceConfiguration.loadFromUserDefaults()
            if let savedTimestamp = config.lastRoll?.timestamp,
               let rollTimestamp = roll.timestamp,
               savedTimestamp > rollTimestamp {
                return false
            }
            config.lastRoll = roll
            config.selectedDice = roll.diceModel
            config.save()
            return true
        }
    }
}

// MARK: - Widget default dice

extension DiceSnapshot {
    /// The dice a widget shows before the person has picked one: a single d20. It is its own
    /// small value, not a preview fixture, so the fixtures can stay out of Release builds.
    /// See CODE_AUDIT_26 §9.46.
    nonisolated static let widgetDefault = DiceSnapshot(
        id: UUID(uuid: (0x22, 0x01, 0xFB, 0xB7, 0x04, 0x03, 0x4A, 0x18, 0xA3, 0x61, 0xCA, 0xD5, 0xA7, 0x6A, 0x63, 0x7E)),
        name: "D20",
        description: "",
        tags: [],
        category: .game,
        displayState: 0,
        dice: [
            DieModel(
                id: UUID(uuid: (0x87, 0xC7, 0xE2, 0x92, 0xDE, 0xFA, 0x45, 0x6B, 0xB0, 0x09, 0x34, 0x1E, 0xDE, 0x85, 0x96, 0x8A)),
                die: RawDie.twenty,
                color: DieModel.ColorCode.G.rawValue,
                rotation: 0.0,
                result: [],
                displayState: 0
            ),
        ],
        sumUp: true,
        modifier: 0.0,
        percentDice: false,
        compareOption: .off,
        compareValue: 0.0,
        coupValues: [],
        coupOnlyOnFirstDie: false,
        fumbleValues: [],
        fumbleOnlyOnFirstDie: false,
        rerollOptions: [],
        reorderDice: false,
        addDiceEvery: 0,
        resultCategory: nil
    )
}

#endif
