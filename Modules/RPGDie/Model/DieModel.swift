// @copyright André Trettin

import AndrenalinKit
import RPGResources
import SwiftUI

public struct DieModel: Equatable, Hashable, Identifiable, Codable, @unchecked Sendable {
    public let id: UUID
    public let die: RawDie
    var rotation: Double = 0
    var result: [Int] = []
    public var displayState: Int = 0
}

extension DieModel {
    public var name: String {
        name(for: 1)
    }
    
    public func name(for number: Int) -> String {
        switch die.sides {
        case .four:
            return "D4G-\(number)"
        case .six:
            return "D6G-\(number)"
        case .eight:
            return "D8G-\(number)"
        case .ten:
            return "D10G-\(number)"
        case .twelve:
            return "D12G-\(number)"
        case .twenty:
            return "D20G-\(number)"
        case .number:
            return "D20-1"
        }
    }

    public func diceImage(for number: Int) -> Image {
        Image(name(for: number), bundle: Resources.bundle)
    }
}

extension DieModel: EntryDataAccessable {
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

    func role(resetResults: Bool = false, reroleOptions: [DiceModel.RerollOption]) -> DieModel {
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

    static var die4: DieModel {
        DieModel(id: UUID(), die: RawDie.four)
    }

    static var die6: DieModel {
        DieModel(id: UUID(), die: RawDie.six)
    }

    static var die8: DieModel {
        DieModel(id: UUID(), die: RawDie.eight)
    }

    static var die10: DieModel {
        DieModel(id: UUID(), die: RawDie.ten)
    }

    static var die12: DieModel {
        DieModel(id: UUID(), die: RawDie.twelve)
    }

    static var die20: DieModel {
        DieModel(id: UUID(), die: RawDie.twenty)
    }
}
