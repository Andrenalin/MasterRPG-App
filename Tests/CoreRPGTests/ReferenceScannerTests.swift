// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_19 §9.18: one parser now handles the four link shapes.
@Suite("Reference scanner")
struct ReferenceScannerTests {
    private let table = UUID()
    private let entry = UUID()

    @Test("All four link shapes are found, with their commands")
    func fourShapes() {
        let text = """
            [A](rpg://TABLE/1/\(table)) \
            [B](rpg://TABLE/2/\(table)/Roll) \
            [C](rpg://TABLE/3/\(table)/\(entry)) \
            [D](rpg://TABLE/4/\(table)/\(entry)/Roll)
            """

        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: text)

        #expect(links.tables.map(\.name).sorted() == ["A", "B"])
        #expect(links.tables.first { $0.name == "B" }?.command == "Roll")
        #expect(links.tables.first { $0.name == "A" }?.command == nil)
        #expect(links.tableEntries.map(\.name).sorted() == ["C", "D"])
        #expect(links.tableEntries.allSatisfy { $0.table == table && $0.entry == entry })
        #expect(links.tableEntries.first { $0.name == "D" }?.command == "Roll")
    }

    @Test("A command link is not mistaken for an entry link")
    func commandIsNotAnEntry() {
        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: "[B](rpg://TABLE/2/\(table)/Roll)")
        #expect(links.tableEntries.isEmpty)
        #expect(links.tables.count == 1)
    }

    @Test("A link whose table is not a UUID is ignored")
    func invalidTableIsIgnored() {
        let links = ReferenceScanner.allUuidUrls(for: "rpg", in: "[X](rpg://TABLE/1/not-a-uuid)")
        #expect(links.tables.isEmpty)
    }
}
