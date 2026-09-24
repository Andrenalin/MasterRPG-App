// @copyright André Trettin

import CoreRPG
import RPGResources
import SwiftUI

public struct DieModel: Equatable, Hashable, Identifiable, Codable, Sendable {
    // Resolving `.Random` to a concrete "A"/"G" skin here, once, at construction
    // time — instead of re-rolling it every time `name(for:)` is read from a
    // SwiftUI view body — is what fixes the flicker where a d4/d20's art asset
    // used to change on every unrelated re-render. See CODE_AUDIT §5.5.
    public init(id: UUID, die: RawDie, color: String = ColorCode.Random.rawValue, rotation: Double = 0, result: [Int] = [], displayState: Int = 0) {
        self.id = id
        self.die = die
        self.color = DieModel.resolvedColor(color, for: die)
        self.rotation = rotation
        self.result = result
        self.displayState = displayState
    }

    private static func resolvedColor(_ color: String, for die: RawDie) -> String {
        guard color == ColorCode.Random.rawValue || color.isEmpty else { return color }
        let codes = die.colorCodes
        let index = RawDie(.number(codes.count)).roll() - 1
        return codes[index].rawValue
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
        case A, B, C, D, G
    }
    
    // The setter is a required no-op, not dead code: `EntryDataAccessable`
    // requires `name` to be `{ get set }` for types that support renaming
    // entries via the shared list-editing UI, but a die has no free-text
    // name of its own to rename (same pattern as `content` below).
    // CODE_AUDIT §9.17 mistakenly flagged this as removable — reverted
    // after the protocol conformance failed to build.
    public var name: String {
        get { name(for: 1) }
        set {}
    }

    func name(for number: Int) -> String {
        // `color` is already resolved to a concrete "A"/"G" skin by the
        // initializer (see CODE_AUDIT §5.5) — this only re-resolves a
        // literal "Random"/empty value that could still reach here from
        // data decoded before that fix (Codable's `init(from:)` reads
        // `color` directly, bypassing the initializer).
        let code = DieModel.resolvedColor(color, for: die)
        return switch die.sides {
        case .two: "D2\(code)-\(number)"
        case .three: "D3\(code)-\(number)"
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
    // These three reconstructions previously omitted `color:`, silently
    // reverting a chosen A/G skin back to `.Random` on every single roll or
    // reset within the same session (compounding the flicker fixed above).
    // See CODE_AUDIT §5.4/§5.5.
    func resetResults() -> DieModel {
        return DieModel(id: id, die: die, color: color)
    }

    func applyResult(values: [Int]) -> DieModel {
        DieModel(id: id, die: die, color: color, rotation: RawDie.rollPercent() * 360, result: values)
    }

    public func roll(resetResults: Bool = false, rerollOptions: [DiceModel.RerollOption]) -> DieModel {
        var rollResult: [Int] = []
        var roll: Int
        var attempts = 0
        // Without this cap, reroll options that cover every face of the die
        // (e.g. one reroll rule per side of a d4) made this loop spin
        // forever, freezing the app. See CODE_AUDIT §5.1.
        let maxAttempts = die.max + 1
        repeat {
            roll = die.roll()
            rollResult.append(roll)
            attempts += 1
        } while attempts < maxAttempts && rerollOptions.contains(where: { $0.number == roll })

        let updatedResult: [Int]
        if resetResults {
            updatedResult = rollResult
        } else {
            updatedResult = result + rollResult
        }
        return DieModel(id: id, die: die, color: color, rotation: (1800 + RawDie.rollPercent() * 360), result: updatedResult)
    }

    // Named per-size shortcuts kept for call-site readability (they're used
    // throughout the module and widget target); each now forwards to one
    // shared helper instead of repeating its own `DieModel(id:die:color:)`
    // call. See CODE_AUDIT §9.6.
    private static func die(_ sides: RawDie.Sides, color: ColorCode) -> DieModel {
        DieModel(id: UUID(), die: RawDie(sides), color: color.rawValue)
    }

    public static var die2: DieModel { die2(color: .Random) }
    public static func die2(color: ColorCode) -> DieModel { die(.two, color: color) }

    public static var die3: DieModel { die3(color: .Random) }
    public static func die3(color: ColorCode) -> DieModel { die(.three, color: color) }

    public static var die4: DieModel { die4(color: .Random) }
    public static func die4(color: ColorCode) -> DieModel { die(.four, color: color) }

    public static var die6: DieModel { die6(color: .Random) }
    public static func die6(color: ColorCode) -> DieModel { die(.six, color: color) }

    public static var die8: DieModel { die8(color: .Random) }
    public static func die8(color: ColorCode) -> DieModel { die(.eight, color: color) }

    public static var die10: DieModel { die10(color: .Random) }
    public static func die10(color: ColorCode) -> DieModel { die(.ten, color: color) }

    public static var die12: DieModel { die12(color: .Random) }
    public static func die12(color: ColorCode) -> DieModel { die(.twelve, color: color) }

    public static var die20: DieModel { die20(color: .Random) }
    public static func die20(color: ColorCode) -> DieModel { die(.twenty, color: color) }
}
