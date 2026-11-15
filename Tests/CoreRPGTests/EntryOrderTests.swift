// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_26 §5.15: a reorder keeps the entries the sheet did not list.
@Suite("Entry order")
struct EntryOrderTests {
    private struct Entry: Equatable {
        let id: UUID
        let name: String
    }

    private let a = Entry(id: UUID(), name: "a")
    private let hidden = Entry(id: UUID(), name: "hidden")
    private let b = Entry(id: UUID(), name: "b")
    private let c = Entry(id: UUID(), name: "c")

    @Test("The listed entries take the new order")
    func reorders() {
        let result = EntryOrder.reordered([a, b, c], by: [c.id, a.id, b.id], id: \.id)
        #expect(result == [c, a, b])
    }

    @Test("A hidden entry that the sheet does not list stays, behind the listed ones")
    func keepsEntriesMissingFromTheIds() {
        let result = EntryOrder.reordered([a, hidden, b, c], by: [c.id, b.id, a.id], id: \.id)
        #expect(result == [c, b, a, hidden])
    }

    @Test("Several unlisted entries keep their relative order")
    func unlistedKeepRelativeOrder() {
        let second = Entry(id: UUID(), name: "second hidden")
        let result = EntryOrder.reordered([hidden, a, second, b], by: [b.id, a.id], id: \.id)
        #expect(result == [b, a, hidden, second])
    }

    @Test("Unknown and repeated ids are ignored")
    func ignoresUnknownAndRepeatedIds() {
        let result = EntryOrder.reordered([a, b], by: [b.id, UUID(), b.id, a.id], id: \.id)
        #expect(result == [b, a])
    }

    @Test("An empty id list leaves the order alone")
    func emptyIds() {
        #expect(EntryOrder.reordered([a, b, c], by: [], id: \.id) == [a, b, c])
    }
}
