// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import TableRPG

@MainActor
struct TableEntryModelTests {
    func setUp() async throws -> TableEntryModel {
        TableEntryModel(
            id: UUID(),
            name: " Hello name",
            content: "Hello Content ",
            displayState: 3,
            diceResult: "Some Result"
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
        #expect(nil == d.diceResult)
        #expect(d.displayState == a.displayState)
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
        sut.diceResult = "My Result"

        let m1 = a.merge(sut)
        #expect(m1.id == a.id)
        #expect(m1.name == sut.name)
        #expect(m1.content == a.content)
        #expect(m1.displayState == sut.displayState)
        #expect(m1.diceResult == sut.diceResult)

        let m2 = sut.merge(a)
        #expect(m2.id == sut.id)
        #expect(m2.name == sut.name)
        #expect(m2.content == a.content)
        #expect(m2.displayState == a.displayState)
        #expect(m2.diceResult == a.diceResult)

        #expect(sut.isSame(a) == false)
        #expect(m1.isSame(m2) == true)
    }

    @Test func entryLinkText() async throws {
        let sut = try await setUp()
        let result1 = "**Hello name**: Hello Content "
        #expect(sut.entryLinkText(otherValue: "") == result1)

        let result2 = "**Hello name**: Hello Content More"
        #expect(sut.entryLinkText(otherValue: "More") == result2)
    }

    @Test func contentDifferenceIsDetected() {
        // Given
        let existing = TableEntryModel.fixture(
            id: .fixture1,
            name: "Shared name",
            content: "Existing content"
        )
        let imported = TableEntryModel.fixture(
            id: .fixture1,
            name: "Shared name",
            content: "Imported content"
        )

        // When / Then
        #expect(existing.name == imported.name)
        #expect(!existing.isSame(imported))
    }
}
#endif
