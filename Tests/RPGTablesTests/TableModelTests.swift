// @copyright André Trettin

#if canImport(Testing)
import AndrenalinKit
import Foundation
import Testing

@testable import TableRPG

struct TableModelTests {
    func setUp() async throws -> TableModel {
        TableModel(
            id: UUID(),
            name: "Hello Dice",
            description: "Hello Desc",
            tags: ["DS", "Second"],
            category: .loot,
            displayState: 2,
            tableType: .dice,
            diceId: UUID(),
            entries: [TableEntryModel(id: UUID(), name: "Base", content: "Content")],
            diceResult: "Some Result"
        )
    }

    @Test func assignAndDuplicate() async throws {
        let sut = try await setUp()
        let a = sut
        #expect(a == sut)

        let d = sut.duplicate()
        #expect(d.id != a.id)
        #expect(d.name == "\(a.name) Copy")
        #expect(d.description == a.description)
        #expect(d.tags == a.tags)
        #expect(d.category == a.category)
        #expect(d.displayState == a.displayState)
        #expect(d.tableType == a.tableType)
        #expect(d.diceId == a.diceId)

        #expect(nil == d.diceResult)
        #expect(d.entries.count == a.entries.count)
        for (index, _) in d.entries.enumerated() {
            #expect(d.entries[index] != a.entries[index])
            #expect(d.entries[index].isSame(a.entries[index]))
        }
    }

    @Test func changeValues() async throws {
        let sut = try await setUp()
        let a = sut.copy()
        let b = sut.copy()
        let c = sut.copy()
        #expect(sut.isSame(a) == true)
        b.diceResult = "some other"
        #expect(sut.isSame(b) == true)
        var entries = b.entries
        entries[0].name = "some other"
        b.entries = entries
        #expect(b.entries[0].name == "some other")
        #expect(sut.isSame(b) == false)
        c.entries = c.entries + [TableEntryModel(id: UUID(), name: "Hi", content: "C")]
        #expect(c.entries.count == 2)
        #expect(sut.isSame(c) == false)

        a.name = "Good"
        #expect(sut.isSame(a) == false)

        sut.description = "New Description"
        sut.tags = ["Second"]
        sut.category = .game
        sut.name = "Take this"
        a.tags = ["DS"]
        a.displayState = 100
        a.tableType = .list
        sut.diceId = UUID()
        a.diceResult = "New result"

        let m1 = a.merge(sut)
        #expect(m1.id == a.id)
        #expect(m1.name == sut.name)
        #expect(m1.description == sut.description)
        #expect(m1.tags == a.tags)
        #expect(m1.category == sut.category)
        #expect(m1.displayState == sut.displayState)
        #expect(m1.tableType == a.tableType)
        #expect(m1.diceId == sut.diceId)
        #expect(m1.diceResult == sut.diceResult)
        #expect(m1.entries == a.entries)

        let m2 = sut.merge(a)
        #expect(m2.id == a.id)
        #expect(m2.name == sut.name)
        #expect(m2.description == sut.description)
        #expect(m2.tags == a.tags)
        #expect(m2.category == sut.category)
        #expect(m2.displayState == a.displayState)
        #expect(m2.tableType == a.tableType)
        #expect(m2.diceId == sut.diceId)
        #expect(m2.diceResult == a.diceResult)
        #expect(m2.entries == sut.entries)
    }
}
#endif
