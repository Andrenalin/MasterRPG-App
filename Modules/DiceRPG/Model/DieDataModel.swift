// @copyright André Trettin

import Foundation
import RPGResources
import SwiftData
import SwiftUI

@Model 
public final class DieDataModel {
    public init(id: UUID, index: Int = 0, die: RawDie = .twenty, color: String = "", rotation: Double = 0, result: [Int] = [], parent: DiceDataModel? = nil) {
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
    var color: String = ColorCode.Random.rawValue
    
    @Transient
    var rotation: Double = 0
    @Transient
    var result: [Int] = []

    //@CodableIgnored
    var parent: DiceDataModel? = nil

    // MARK: - Codable
    
    struct DieDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(id: UUID = UUID(), index: Int = 0, die: RawDie = RawDie.twenty, color: String = ColorCode.Random.rawValue, rotation: Double = 0, result: [Int] = []) {
            self.id = id
            self.index = index
            self.die = die
            self.color = color
            self.rotation = rotation
            self.result = result
        }
        var id: UUID = UUID()
        var index: Int = 0
        var die: RawDie = RawDie.twenty
        var color: String = ColorCode.Random.rawValue
        var rotation: Double = 0
        var result: [Int] = []
    }
    
    convenience init(_ model: DieDataModelCodable) {
        self.init(id: model.id, index: model.index, die: model.die, color: model.color, rotation: model.rotation, result: model.result)
    }
    
    var codableModel: DieDataModelCodable {
        DieDataModelCodable(
            id: id,
            index: index,
            die: die,
            color: color,
            rotation: rotation,
            result: result
        )
    }
    
    func replace(_ model: DieDataModelCodable) {
        id = model.id
        index = model.index
        die = model.die
        color = model.color
        rotation = model.rotation
        result = model.result
    }
}

extension DieDataModel {
    enum ColorCode: String {
        case Random
        case A, G
    }
    
    var name: String {
        name(for: 1)
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
        DieDataModel(id: UUID(), index: index, die: die, color: color)
    }

    func resetResults() {
        result = []
    }
    
    func role(resetResults: Bool = false, reroleOptions: [DiceDataModel.RerollOption]) {
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
        die4(color: .Random)
    }

    static func die4(color: ColorCode) -> DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.four, color: color.rawValue)
    }

    static var die6: DieDataModel {
        die6(color: .Random)
    }

    static func die6(color: ColorCode) -> DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.six, color: color.rawValue)
    }

    static var die8: DieDataModel {
        die8(color: .Random)
    }

    static func die8(color: ColorCode) -> DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.eight, color: color.rawValue)
    }

    static var die10: DieDataModel {
        die10(color: .Random)
    }

    static func die10(color: ColorCode) -> DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.ten, color: color.rawValue)
    }

    static var die12: DieDataModel {
        die12(color: .Random)
    }

    static func die12(color: ColorCode) -> DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.twelve, color: color.rawValue)
    }

    static var die20: DieDataModel {
        die20(color: .Random)
    }
    
    static func die20(color: ColorCode) -> DieDataModel {
        DieDataModel(id: UUID(), die: RawDie.twenty, color: color.rawValue)
    }
}
