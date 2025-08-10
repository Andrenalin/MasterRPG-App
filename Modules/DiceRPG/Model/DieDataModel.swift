// @copyright André Trettin

import Foundation
import RPGResources
import SwiftData
import SwiftUI

@Model
public final class DieDataModel {
    public init(id: UUID, index: Int = 0, die: RawDie = .twenty, rotation: Double = 0, result: [Int] = [], parent: DiceConfigDataModel? = nil) {
        self.id = id
        self.index = index
        self.die = die
        self.rotation = rotation
        self.result = result
    }
    
    public var id: UUID = UUID()
    var index: Int = 0
    var die: RawDie = RawDie.twenty
    
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
        switch die.sides {
        case .four: "D4G-\(number)"
        case .six: "D6G-\(number)"
        case .eight: "D8G-\(number)"
        case .ten: "D10G-\(number)"
        case .twelve: "D12G-\(number)"
        case .twenty: "D20G-\(number)"
        case .number: "D20-1"
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
