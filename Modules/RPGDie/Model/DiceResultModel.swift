// @copyright André Trettin

import AndrenalinKit
import Foundation
import os.log

struct DiceResultModel: Equatable, Hashable, Codable {
    let diceModel: DiceModel
    var result: DiceResult
    var values: String
    var sum: Int
    var checked: Bool
    
    enum DiceResult: Equatable, Hashable, Codable {
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
    
    init(diceModel: DiceModel) {
        self.diceModel = diceModel
        self.result = .notRolled
        self.values = ""
        self.sum = 0
        self.checked = false
    }
    
    init(diceModel: DiceModel, result: DiceResult, values: String, sum: Int, checked: Bool) {
        self.diceModel = diceModel
        self.result = result
        self.values = values
        self.sum = sum
        self.checked = checked
    }
}

extension DiceResultModel {
    func encodeData() -> Data? {
        let encoder = JSONEncoder()
        return try? encoder.encode(self)
    }

    static func decodeData(of data: Data?) -> Self? {
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
