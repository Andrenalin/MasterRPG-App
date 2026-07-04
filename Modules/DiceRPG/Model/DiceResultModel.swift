// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

public struct DiceResultModel: Equatable, Hashable, Codable, Sendable, Identifiable {
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
            case .coup: "Coup"
            case .fumble: "Fumble"
            case .rolled: "Rolled"
            case .notRolled: "Not rolled"
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
    @MainActor
    init(diceModel: DiceModel) {
        self.init(diceModel: DiceSnapshot(diceModel))
    }

    @MainActor
    init(diceModel: DiceModel, result: DiceResult, values: String, sum: Int, checked: Bool, timeStamp: Date = Date.now) {
        self.init(diceModel: DiceSnapshot(diceModel), result: result, values: values, sum: sum, checked: checked, timeStamp: timeStamp)
    }
}

extension DiceResultModel {
    public func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }

    public static func decodeData(of data: Data?) -> Self? {
        guard let data else { return nil }
        let decoder = JSONDecoder()
        do {
            return try decoder.decode(Self.self, from: data)
        } catch {
            Logger.codable.error("DiceResultModel error \(error, privacy: .public)")
        }
        return nil
    }
}
