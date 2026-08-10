// @copyright André Trettin

import CoreRPG
import RPGResources
import SwiftUI

public struct DieModel: Equatable, Hashable, Identifiable, Codable, Sendable {
    public init(id: UUID, die: RawDie, color: String = ColorCode.Random.rawValue, rotation: Double = 0, result: [Int] = [], displayState: Int = 0) {
        self.id = id
        self.die = die
        self.color = color
        self.rotation = rotation
        self.result = result
        self.displayState = displayState
    }
    
    public let id: UUID
    public let die: RawDie
    
    var color: String = ColorCode.Random.rawValue
    
    var rotation: Double = 0
    public var result: [Int] = []
    public var displayState: Int = 0
    
    private enum CodingKeys: CodingKey {
        case id
        case die
        case color
        case rotation
        case result
        case displayState
    }
    
    public init(from decoder: any Decoder) throws {
        let container: KeyedDecodingContainer<DieModel.CodingKeys> = try decoder.container(keyedBy: DieModel.CodingKeys.self)
        
        self.id = try container.decode(UUID.self, forKey: DieModel.CodingKeys.id)
        self.die = try container.decode(RawDie.self, forKey: DieModel.CodingKeys.die)
        self.color = try container.decodeIfPresent(String.self, forKey: DieModel.CodingKeys.color) ?? "G"
        self.rotation = try container.decode(Double.self, forKey: DieModel.CodingKeys.rotation)
        self.result = try container.decode([Int].self, forKey: DieModel.CodingKeys.result)
        self.displayState = try container.decode(Int.self, forKey: DieModel.CodingKeys.displayState)
        
    }
    
    public func encode(to encoder: any Encoder) throws {
        var container: KeyedEncodingContainer<DieModel.CodingKeys> = encoder.container(keyedBy: DieModel.CodingKeys.self)
        
        try container.encode(self.id, forKey: DieModel.CodingKeys.id)
        try container.encode(self.die, forKey: DieModel.CodingKeys.die)
        try container.encode(self.color, forKey: DieModel.CodingKeys.color)
        try container.encode(self.rotation, forKey: DieModel.CodingKeys.rotation)
        try container.encode(self.result, forKey: DieModel.CodingKeys.result)
        try container.encode(self.displayState, forKey: DieModel.CodingKeys.displayState)
    }
}

extension DieModel {
    public enum ColorCode: String {
        case Random
        case A, G
    }
    
    public var name: String {
        get { name(for: 1) }
        set {}
    }

    func name(for number: Int) -> String {
        var code = color
        if die.sides == .four || die.sides == .twenty {
            if color == ColorCode.Random.rawValue || color.isEmpty {
                if RawDie(.number(2)).role() == 1 {
                    code = ColorCode.A.rawValue
                } else {
                    code = ColorCode.G.rawValue
                }
            }
        } else {
            code = ColorCode.G.rawValue
        }
        return switch die.sides {
        case .four: "D4\(code)-\(number)"
        case .six: "D6\(code)-\(number)"
        case .eight: "D8\(code)-\(number)"
        case .ten: "D10\(code)-\(number)"
        case .twelve: "D12\(code)-\(number)"
        case .twenty: "D20\(code)-\(number)"
        case .number: "D20\(code)-1"
        }
    }

    public func diceImage(for number: Int) -> Image {
        Image(name(for: number), bundle: RPGResources.Resources.bundle)
    }
}

extension DieModel: EntryDataAccessable {
    public var content: String {
        get { "" }
        set {}
    }
    public var childId: UUID { id }
    public static func newChild(id: UUID) -> Self {
        empty(id)
    }

    public static var empty: DieModel { empty(UUID()) }
    public static func empty(_ id: UUID) -> DieModel {
        DieModel(id: id, die: RawDie.twenty)
    }

    public func duplicate() -> DieModel {
        DieModel(id: UUID(), die: die)
    }
    
    public func filter(with search: String) -> Bool {
        true
    }
}

extension DieModel: ItemDiffComparable {
    public func merge(_ other: DieModel) -> DieModel {
        other
    }

    public func isSame(_ other: DieModel) -> Bool {
        die == other.die
    }
}

extension DieModel {
    func resetResults() -> DieModel {
        return DieModel(id: id, die: die)
    }

    func applyResult(values: [Int]) -> DieModel {
        DieModel(id: id, die: die, rotation: RawDie.rolePercent() * 360, result: values)
    }

    public func role(resetResults: Bool = false, reroleOptions: [DiceModel.RerollOption]) -> DieModel {
        var roleResult: [Int] = []
        var role: Int
        repeat {
            role = die.role()
            roleResult.append(role)
        } while reroleOptions.contains(where: { $0.number == role })

        let updatedResult: [Int]
        if resetResults {
            updatedResult = roleResult
        } else {
            updatedResult = result + roleResult
        }
        return DieModel(id: id, die: die, rotation: (1800 + RawDie.rolePercent() * 360), result: updatedResult)
    }

    public static var die4: DieModel {
        die4(color: .Random)
    }

    public static func die4(color: ColorCode) -> DieModel {
        DieModel(id: UUID(), die: RawDie.four, color: color.rawValue)
    }

    public static var die6: DieModel {
        die6(color: .Random)
    }

    public static func die6(color: ColorCode) -> DieModel {
        DieModel(id: UUID(), die: RawDie.six, color: color.rawValue)
    }

    public static var die8: DieModel {
        die8(color: .Random)
    }

    public static func die8(color: ColorCode) -> DieModel {
        DieModel(id: UUID(), die: RawDie.eight, color: color.rawValue)
    }

    public static var die10: DieModel {
        die10(color: .Random)
    }

    public static func die10(color: ColorCode) -> DieModel {
        DieModel(id: UUID(), die: RawDie.ten, color: color.rawValue)
    }

    public static var die12: DieModel {
        die12(color: .Random)
    }

    public static func die12(color: ColorCode) -> DieModel {
        DieModel(id: UUID(), die: RawDie.twelve, color: color.rawValue)
    }

    public static var die20: DieModel {
        die20(color: .Random)
    }
    
    public static func die20(color: ColorCode) -> DieModel {
        DieModel(id: UUID(), die: RawDie.twenty, color: color.rawValue)
    }
}
