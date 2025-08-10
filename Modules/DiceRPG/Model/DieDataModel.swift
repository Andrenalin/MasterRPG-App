// @copyright André Trettin

import Foundation
import RPGResources
import SwiftData
import SwiftUI

@Model
public final class DieDataModel {
    public init(id: UUID, index: Int = 0, die: RawDie = .twenty, color: String = "", rotation: Double = 0, result: [Int] = [], parent: DiceConfigDataModel? = nil) {
        self.id = id
        self.index = index
        self.die = die
        self.color = color
        self.rotation = rotation
        self.result = result
    }
    
    public var id: UUID = UUID()
    var index: Int = 0
    var die: RawDie = RawDie.twenty
    var color: String = ""
    
    @Transient
    var rotation: Double = 0
    @Transient
    var result: [Int] = []
    
    var parent: DiceConfigDataModel? = nil
}

extension DieDataModel {
    var name: String {
        name(for: 1)
    }
    
    func name(for number: Int) -> String {
        var code = color
        if die.sides == .four || die.sides == .twenty {
            if color.isEmpty {
                if RawDie(.number(2)).role() == 1 {
                    code = "A"
                } else {
                    code = "G"
                }
            }
        } else {
            code = "G"
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

    func diceImage(for number: Int) -> Image {
        Image(name(for: number), bundle: Resources.bundle)
    }
}

extension DieDataModel {
    func applyResult(values: [Int]) {
        result = values
        rotation = RawDie.rolePercent() * 360
    }
    
    func duplicate(index: Int) -> DieDataModel {
        DieDataModel(id: UUID(), index: index, die: die)
    }

    func resetResults() {
        result = []
    }
    
    func role(resetResults: Bool = false, reroleOptions: [DiceConfigDataModel.RerollOption]) {
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
        result = updatedResult
        rotation = (1800 + RawDie.rolePercent() * 360)
    }
}

extension DieDataModel {
    static var die4: DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.four)
    }

    static var die6: DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.six)
    }

    static var die8: DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.eight)
    }

    static var die10: DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.ten)
    }

    static var die12: DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.twelve)
    }

    static var die20: DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.twenty)
    }
}
