// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_18 §5.12: re-derived links get the same id on every device.
@Suite("Link register occurrence ids")
struct LinkRegisterOccurrenceIdTests {
    private let source = ItemRowModel(itemId: UUID(), entryId: UUID(), typeId: .adventure)
    private let destination = ItemRowModel(itemId: UUID(), typeId: .map)

    @Test("The same occurrence always gets the same id")
    func sameOccurrenceSameId() {
        let first = LinkRegisterModel(name: "Map", source: source, destination: destination, linkNumber: 2)
        let second = LinkRegisterModel(name: "Renamed", source: source, destination: destination, linkNumber: 2)
        #expect(first.id == second.id)
    }

    @Test("Different occurrences get different ids")
    func differentOccurrencesDifferentIds() {
        let first = LinkRegisterModel(name: "Map", source: source, destination: destination, linkNumber: 1)
        let second = LinkRegisterModel(name: "Map", source: source, destination: destination, linkNumber: 2)
        let command = LinkRegisterModel(name: "Map", source: source, destination: destination, linkNumber: 1, command: "show")
        #expect(first.id != second.id)
        #expect(first.id != command.id)
    }

    @Test("A stored id is kept")
    func storedIdIsKept() {
        let stored = UUID()
        #expect(LinkRegisterModel(id: stored, name: "", source: source, destination: destination).id == stored)
    }
}
