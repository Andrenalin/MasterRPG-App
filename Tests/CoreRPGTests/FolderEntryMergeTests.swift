// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

/// CODE_AUDIT_18 §9.9: the folder-entry union is deterministic and order-independent.
@Suite("Folder entry merge")
struct FolderEntryMergeTests {
    private struct Entry: Equatable {
        let id: UUID
        let name: String
    }

    @Test("Equal names are ordered by id, independent of which side is local")
    func deterministicOrder() {
        let a = Entry(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!, name: "Goblin")
        let b = Entry(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!, name: "Goblin")
        let c = Entry(id: UUID(uuidString: "00000000-0000-0000-0000-00000000000C")!, name: "Axe")
        let forward = FolderEntryMerge.merged(local: [b, c], remote: [a], id: \.id, name: \.name)
        let backward = FolderEntryMerge.merged(local: [a], remote: [c, b], id: \.id, name: \.name)
        #expect(forward == [c, a, b])
        #expect(backward == forward)
    }

    @Test("An id on both sides is combined once")
    func sharedIdIsCombined() {
        let id = UUID()
        let merged = FolderEntryMerge.merged(
            local: [Entry(id: id, name: "Local")],
            remote: [Entry(id: id, name: "Remote")],
            id: \.id,
            name: \.name,
            combine: { _, remote in remote }
        )
        #expect(merged == [Entry(id: id, name: "Remote")])
    }
}
