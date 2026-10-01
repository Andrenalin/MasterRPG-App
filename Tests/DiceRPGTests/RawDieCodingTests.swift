// @copyright André Trettin

import Foundation
import Testing

@testable import DiceRPG

/// CODE_AUDIT_18 §5.8 / §5.9: d3 keeps its legacy wire format, and colours without art fall
/// back to one that has art.
@Suite("Raw die coding and colours")
struct RawDieCodingTests {
    /// The synthesized shape of `Sides` before the `.three` case existed.
    private enum LegacySides: Codable, Equatable {
        case two, four, six, eight, ten, twelve, twenty
        case number(Int)
    }

    @Test("A d3 encodes in the legacy .number(3) shape")
    func threeEncodesAsLegacyNumber() throws {
        let data = try JSONEncoder().encode(RawDie.Sides.three)
        #expect(try JSONDecoder().decode(LegacySides.self, from: data) == .number(3))
    }

    @Test("The legacy .number(3) shape decodes as .three")
    func legacyNumberThreeDecodesAsThree() throws {
        let data = try JSONEncoder().encode(LegacySides.number(3))
        #expect(try JSONDecoder().decode(RawDie.Sides.self, from: data) == .three)
    }

    /// CODE_AUDIT_19 §5.14: builds `c2d185f2`…`354e3893` wrote a d3 as `{"three":{}}`.
    @Test("The interim {\"three\":{}} shape decodes as .three")
    func interimThreeShapeDecodes() throws {
        let data = Data(#"{"three":{}}"#.utf8)
        #expect(try JSONDecoder().decode(RawDie.Sides.self, from: data) == .three)
    }

    @Test("Other sides round-trip unchanged", arguments: [
        RawDie.Sides.two, .four, .six, .eight, .ten, .twelve, .twenty, .number(7), .number(100)
    ])
    func sidesRoundTrip(sides: RawDie.Sides) throws {
        let data = try JSONEncoder().encode(sides)
        #expect(try JSONDecoder().decode(RawDie.Sides.self, from: data) == sides)
    }

    @Test("A colour without art for the die falls back to one with art")
    func unsupportedColourFallsBack() {
        let die = DieModel(id: UUID(), die: .twelve, color: DieModel.ColorCode.E.rawValue)
        #expect(die.name(for: 1) == "D12G-1")
        let supported = DieModel(id: UUID(), die: .twelve, color: DieModel.ColorCode.C.rawValue)
        #expect(supported.name(for: 1) == "D12C-1")
    }
}
