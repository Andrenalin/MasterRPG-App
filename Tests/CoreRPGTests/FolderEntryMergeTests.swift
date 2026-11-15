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

    @Test("The order does not depend on the language: capitals sort before lowercase, accents after")
    func orderIsLiteral() {
        // A localized compare would give apple, Äpfel, Zebra in English and a different order in
        // other languages; the literal compare is the same on every device. CODE_AUDIT_26 §5.53.
        let names = ["Zebra", "Äpfel", "apple", "Éclair", "eclair"]
        let entries = names.map { Entry(id: UUID(), name: $0) }
        let merged = FolderEntryMerge.merged(local: entries, remote: [], id: \.id, name: \.name)
        #expect(merged.map(\.name) == ["Zebra", "apple", "eclair", "Äpfel", "Éclair"])
        let reversed = FolderEntryMerge.merged(local: [], remote: entries.reversed(), id: \.id, name: \.name)
        #expect(reversed.map(\.name) == merged.map(\.name))
    }
}
