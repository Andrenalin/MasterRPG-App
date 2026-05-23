// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import AdventureRPG

struct AdventureEntryModelTests {
    func setUp() async throws -> AdventureEntryModel {
        AdventureEntryModel(
            id: UUID(),
            name: "My Name",
            content: "My Desc",
            displayState: 23
        )
    }

    @Test func assignAndDuplicate() async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.id != a.id)
        #expect(d.name == a.name)
        #expect(d.content == a.content)
        #expect(d.displayState == a.displayState)

        #expect(d.isSame(a))
    }

    @Test func changeValues() async throws {
        var sut = try await setUp()
        var a = sut
        #expect(sut.isSame(a) == true)

        a.name = "Good"
        #expect(sut.isSame(a) == false)

        sut.content = "My Content"
        sut.name = "Better"
        a.content = "Take this"
        a.displayState = 100

        let m1 = a.merge(sut)
        #expect(m1.id == a.id)
        #expect(m1.name == sut.name)
        #expect(m1.content == a.content)
        #expect(m1.displayState == sut.displayState)

        let m2 = sut.merge(a)
        #expect(m2.id == sut.id)
        #expect(m2.name == sut.name)
        #expect(m2.content == a.content)
        #expect(m2.displayState == a.displayState)

        #expect(sut.isSame(a) == false)
        #expect(m1.isSame(m2) == true)
    }
}
#endif
