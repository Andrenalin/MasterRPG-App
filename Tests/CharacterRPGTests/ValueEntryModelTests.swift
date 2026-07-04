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

    @Test func calculate() async throws {
        var sut = setUp()
        sut.reset(valueType: .number)

        var start = "12+601"
        sut.value = start
        await #expect(Calculator.calculate(start) == 613.0)

        start = "2"
        sut.value = start
        await #expect(Calculator.calculate(start) == 2.0)
        start = " 2"
        sut.value = start
        await #expect(Calculator.calculate(start) == 2.0)

        start = "2-"
        sut.value = start
        await #expect(Calculator.calculate(start) == nil)

        start = "2+"
        sut.value = start
        await #expect(Calculator.calculate(start) == nil)

        start = "2-6"
        sut.value = start
        await #expect(Calculator.calculate(start) == -4.0)

        start = "2*6"
        sut.value = start
        await #expect(Calculator.calculate(start) == 12.0)

        sut.reset(valueType: .decimal)
        start = "7/2 + 1+2*3"
        sut.value = start
        await #expect(Calculator.calculate(start) == 10.5)

        sut.reset(valueType: .number)
        start = "4 +6 -4* 2+4 *  3"
        sut.value = start
        await #expect(Calculator.calculate(start) == 14.0)
        start = "4+6-4*2+4*3"
        sut.value = start
        await #expect(Calculator.calculate(start) == 14.0)

        sut.reset(valueType: .decimal)
        start = "4/2 +6/2 -4/2* 2+4 *  3"
        sut.value = start
        await #expect(Calculator.calculate(start) == 13.0)
        start = "4/2+6/2-4/2*2+4*3"
        sut.value = start
        await #expect(Calculator.calculate(start) == 13.0)

        start = "4+0+10+2+2 +2+ 10"
        sut.value = start
        await #expect(Calculator.calculate(start) == 30.0)

        start = "4+0+1+2+ 2"
        sut.value = start
        await #expect(Calculator.calculate(start) == 9.0)

        start = "252+4+1400-140+1"
        sut.value = start
        await #expect(Calculator.calculate(start) == 1517.0)
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
}
#endif
