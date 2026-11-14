// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import CharacterRPG

@MainActor
struct ValueEntryModelTests {
    func setUp() -> ValueEntryModel {
        ValueEntryModel(
            id: UUID(),
            name: "MyName",
            type: .number,
            isGenerator: false,
            value: "Cool",
            diceId: UUID(),
            valueId: UUID(),
            displayState: 3
        )
    }

    @Test func assignAndDuplicate() async throws {
        let sut = setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.id != a.id)
        #expect(d.name == a.name)
        #expect(d.type == a.type)
        #expect(d.value == a.value)
        #expect(d.diceId == a.diceId)
        #expect(d.valueId == a.valueId)
        #expect(d.displayState == a.displayState)
    }

    @Test func changeValues() async throws {
        var sut = setUp()
        var a = sut
        #expect(sut.isSame(a) == true)

        a.name = "Good"
        #expect(sut.isSame(a) == false)

        var m1 = a.merge(sut)
        #expect(m1.id == a.id)
        #expect(m1.name == a.name)

        sut.reset(valueType: .decimal)
        m1 = a.merge(sut)
        #expect(m1.type == sut.type)

        sut.name = "Better"
        m1 = a.merge(sut)
        #expect(m1.name == sut.name)

        a.value = "Take this"
        m1 = a.merge(sut)
        #expect(m1.value == a.value)

        a.displayState = 100

        m1 = a.merge(sut)
        #expect(m1.id == a.id)
        #expect(m1.name == sut.name)
        #expect(m1.type == sut.type)
        #expect(m1.value == a.value)
        #expect(m1.displayState == sut.displayState)

        let m2 = sut.merge(a)
        #expect(m2.id == sut.id)
        #expect(m2.name == sut.name)
        #expect(m2.type == sut.type)
        #expect(m2.value == a.value)
        #expect(m2.displayState == a.displayState)

        #expect(sut.isSame(a) == false)
        #expect(m1.isSame(m2) == true)
    }

    @Test func valueText() async throws {
        var sut = setUp()
        var result = sut.valueLinkText(otherValue: "")
        var expResult = "**MyName**: Cool"
        #expect(expResult == result)

        expResult = "**MyName**: CoolMore"
        result = sut.valueLinkText(otherValue: "More")
        #expect(expResult == result)

        sut.name = "Group"
        expResult = "Cool"
        result = sut.valueLinkText(otherValue: "")
        #expect(expResult == result)

        sut.reset(valueType: .text)
        sut.valueId = nil
        expResult = "**Group**: Cool"
        result = sut.valueLinkText(otherValue: "")
        #expect(expResult == result)
    }

    @Test func valueSpecificDifferencesAreDetected() {
        // Given
        let existing = ValueEntryModel.fixture(
            id: .fixture1,
            name: "Shared name",
            type: .number,
            value: "42",
            diceId: .fixture2,
            valueId: .fixture4
        )
        var typeChanged = existing
        typeChanged.type = .decimal
        var diceChanged = existing
        diceChanged.diceId = .fixture3
        var valueLinkChanged = existing
        valueLinkChanged.valueId = .fixture5

        // When / Then
        for changed in [typeChanged, diceChanged, valueLinkChanged] {
            #expect(existing.name == changed.name)
            #expect(existing.content == changed.content)
            #expect(!existing.isSame(changed))
        }
    }

    @Test("A step keeps its precision: a fraction times its divisor is exact, binary noise is gone")
    func calculateKeepsPrecision() {
        #expect(Calculator.calculate("1/3*3") == 1.0)
        #expect(Calculator.calculate("2/3*3") == 2.0)
        #expect(Calculator.calculate("0.1+0.2") == 0.3)
        #expect(Calculator.calculate("10/4") == 2.5)
        #expect(Calculator.calculate("100000*100000") == 10_000_000_000)
    }

    @Test("A decimal result is plain text the calculator can read back, never exponent form (CODE_AUDIT §5.3)")
    func decimalResultHasNoExponent() {
        var sut = setUp()
        sut.reset(valueType: .decimal)

        for (input, expected) in [("1/100000", 0.00001), ("1/3*3", 1.0), ("10/4", 2.5), ("2000000*3000000", 6_000_000_000_000.0)] {
            let text = sut.calculate(on: input)
            #expect(!text.localizedStandardContains("e"), "\(input) gave \(text)")
            #expect(Calculator.calculate(text) == expected, "\(input) gave \(text)")
        }
    }

    @Test("Setting a decimal value on a number entry never traps (CODE_AUDIT §5.4)", arguments: [
        (Double.nan, 0), (.infinity, Int.max), (-.infinity, Int.min), (1e30, Int.max), (-1e30, Int.min), (7.9, 7), (-7.9, -7)
    ])
    func truncatedIntIsTotal(value: Double, expected: Int) {
        #expect(ValueEntryModel.truncatedInt(value) == expected)

        var sut = setUp()
        sut.reset(valueType: .number)
        sut.valueDecimal = value
        #expect(sut.valueNumber == expected)
    }

    @Test("Repeated calculations give the same result from the shared patterns")
    func calculateIsRepeatable() {
        for _ in 0..<3 {
            #expect(Calculator.calculate("4 +6 -4* 2+4 *  3") == 14)
            #expect(Calculator.calculate("4 +-2.0+12") == 14)
        }
    }

    @Test func calculate() async throws {
        var sut = setUp()
        sut.reset(valueType: .number)

        var start = "12+601"
        sut.value = start
        #expect(Calculator.calculate(start) == 613.0)

        start = "2"
        sut.value = start
        #expect(Calculator.calculate(start) == 2.0)
        start = " 2"
        sut.value = start
        #expect(Calculator.calculate(start) == 2.0)

        start = "2-"
        sut.value = start
        #expect(Calculator.calculate(start) == nil)

        start = "2+"
        sut.value = start
        #expect(Calculator.calculate(start) == nil)

        start = "2-6"
        sut.value = start
        #expect(Calculator.calculate(start) == -4.0)

        start = "2*6"
        sut.value = start
        #expect(Calculator.calculate(start) == 12.0)

        sut.reset(valueType: .decimal)
        start = "7/2 + 1+2*3"
        sut.value = start
        #expect(Calculator.calculate(start) == 10.5)

        sut.reset(valueType: .number)
        start = "4 +6 -4* 2+4 *  3"
        sut.value = start
        #expect(Calculator.calculate(start) == 14.0)
        start = "4+6-4*2+4*3"
        sut.value = start
        #expect(Calculator.calculate(start) == 14.0)

        sut.reset(valueType: .decimal)
        start = "4/2 +6/2 -4/2* 2+4 *  3"
        sut.value = start
        #expect(Calculator.calculate(start) == 13.0)
        start = "4/2+6/2-4/2*2+4*3"
        sut.value = start
        #expect(Calculator.calculate(start) == 13.0)

        start = "4+0+10+2+2 +2+ 10"
        sut.value = start
        #expect(Calculator.calculate(start) == 30.0)

        start = "4+0+1+2+ 2"
        sut.value = start
        #expect(Calculator.calculate(start) == 9.0)

        start = "252+4+1400-140+1"
        sut.value = start
        #expect(Calculator.calculate(start) == 1517.0)
    }
    
    @Test func valueNumber() async throws {
        var sut = setUp()
        sut.reset(valueType: .number)
        sut.value = "27"
        
        #expect(sut.valueNumber == 0)

        sut.value = "27|2"
        #expect(sut.valueNumber == 2)

        sut.value = "27|-3"
        #expect(sut.valueNumber == -3)
    }

    @Test("Only a number or decimal entry that is no group can be calculated")
    func canCalculate() {
        for type in ValueEntryModel.ValueType.allCases {
            let plain = ValueEntryModel(id: UUID(), name: "Plain", type: type, value: "1")
            #expect(plain.canCalculate == (type == .number || type == .decimal), "plain \(type)")

            let group = ValueEntryModel(id: UUID(), name: "Group", type: type, value: "", valueId: UUID())
            #expect(!group.canCalculate, "a group entry of type \(type) has no number of its own")
        }
    }
}
#endif
