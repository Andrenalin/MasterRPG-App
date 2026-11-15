// @copyright André Trettin

import CoreRPG
import Foundation

public struct DiceResultModel: Equatable, Hashable, Codable, Sendable, Identifiable, MessageMapper {
    public let id: UUID
    // Value snapshot — this struct crosses process/actor boundaries
    // (game network, widget storage, Live Activity content state).
    public let diceModel: DiceSnapshot
    public var result: DiceResult
    public var values: String
    public var sum: Int
    public var checked: Bool
    public let timestamp: Date?
    
    public enum DiceResult: Equatable, Hashable, Codable, Sendable {
        case coup
        case fumble
        case rolled
        case notRolled
        
        public var localizedTitle: LocalizedStringResource {
            switch self {
            case .coup: LocalizedStringResource("Coup", bundle: .module)
            case .fumble: LocalizedStringResource("Fumble", bundle: .module)
            case .rolled: LocalizedStringResource("Rolled", bundle: .module)
            case .notRolled: LocalizedStringResource("Not rolled", bundle: .module)
            }
        }
    }
    
    public init(diceModel: DiceSnapshot) {
        self.id = UUID()
        self.diceModel = diceModel
        self.result = .notRolled
        self.values = ""
        self.sum = 0
        self.checked = false
        self.timestamp = Date.now
    }
    
    public init(diceModel: DiceSnapshot, result: DiceResult, values: String, sum: Int, checked: Bool, timeStamp: Date = Date.now) {
        self.id = UUID()
        self.diceModel = diceModel
        self.result = result
        self.values = values
        self.sum = sum
        self.checked = checked
        self.timestamp = timeStamp
    }
}

public extension DiceResultModel {
    /// The result as it is sent to the game: the same roll with a reduced snapshot. See
    /// `DiceSnapshot.reducedForRoll()`, CODE_AUDIT_26 §6.8.
    func reducedForSharing() -> DiceResultModel {
        var reduced = DiceResultModel(
            diceModel: diceModel.reducedForRoll(),
            result: result,
            values: values,
            sum: sum,
            checked: checked,
            timeStamp: timestamp ?? Date.now
        )
        reduced = reduced.with(id: id, timestamp: timestamp)
        return reduced
    }
}

extension DiceResultModel {
    fileprivate func with(id: UUID, timestamp: Date?) -> DiceResultModel {
        DiceResultModel(id: id, diceModel: diceModel, result: result, values: values, sum: sum, checked: checked, timestamp: timestamp)
    }

    fileprivate init(id: UUID, diceModel: DiceSnapshot, result: DiceResult, values: String, sum: Int, checked: Bool, timestamp: Date?) {
        self.id = id
        self.diceModel = diceModel
        self.result = result
        self.values = values
        self.sum = sum
        self.checked = checked
        self.timestamp = timestamp
    }
}

public extension DiceResultModel {
    /// Bounds for a roll another device reports. The master cannot re-roll a player's dice, but
    /// it can refuse absurd values (forged sums, oversized payloads, hundreds of dice) that
    /// would otherwise set initiative or trigger a table outcome. See CODE_AUDIT_15 §5.9.
    static let maximumReportedValuesLength = 512
    static let maximumReportedDiceCount = 100
    static let maximumReportedSum = 1_000_000

    /// Whether a roll reported by a peer is within sane bounds.
    var isPlausibleReport: Bool {
        values.count <= Self.maximumReportedValuesLength
            && diceModel.dice.count <= Self.maximumReportedDiceCount
            && sum.magnitude <= UInt(Self.maximumReportedSum)
    }
}

public extension DiceResultModel {
    @MainActor
    init(diceModel: DiceModel) {
        self.init(diceModel: DiceSnapshot(diceModel))
    }

    @MainActor
    init(diceModel: DiceModel, result: DiceResult, values: String, sum: Int, checked: Bool, timeStamp: Date = Date.now) {
        self.init(diceModel: DiceSnapshot(diceModel), result: result, values: values, sum: sum, checked: checked, timeStamp: timeStamp)
    }
}

