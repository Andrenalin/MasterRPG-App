// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import RuleRPG

/// CODE_AUDIT_26 §10.7: reordered and duplicate-named entries in `mergeEntries`, and the player
/// export.
@Suite("Rule merge risks")
@MainActor
struct RuleMergeRiskTests {
    @Test("Two same-named imported entries take two different existing entries")
    func duplicateNamesTakeDistinctIdentities() throws {
        let firstId = try #require(UUID(uuidString: "A1000000-0000-4000-8000-000000000001"))
        let secondId = try #require(UUID(uuidString: "A1000000-0000-4000-8000-000000000002"))
        let existing = [
            RuleEntryModel.fixture(id: firstId, name: "Notes", content: "one", kind: .value),
            RuleEntryModel.fixture(id: secondId, name: "Notes", content: "two", kind: .value)
        ]
        let imported = [
            RuleEntryModel.fixture(id: UUID(), name: "Notes", content: "uno", kind: .value),
            RuleEntryModel.fixture(id: UUID(), name: "Notes", content: "dos", kind: .value)
        ]

        let merged = EditController.mergeEntries(existing: existing, imported: imported)

        #expect(merged.count == 2)
        #expect(Set(merged.map(\.id)).count == 2)
    }

    @Test("Reordered existing entries keep their identity and the imported order")
    func reorderedEntriesKeepIdentity() throws {
        let aId = try #require(UUID(uuidString: "B2000000-0000-4000-8000-00000000000A"))
        let bId = try #require(UUID(uuidString: "B2000000-0000-4000-8000-00000000000B"))
        let existing = [
            RuleEntryModel.fixture(id: aId, name: "A", content: "a", kind: .value),
            RuleEntryModel.fixture(id: bId, name: "B", content: "b", kind: .value)
        ]
        let imported = [
            RuleEntryModel.fixture(id: bId, name: "B", content: "b2", kind: .value),
            RuleEntryModel.fixture(id: aId, name: "A", content: "a2", kind: .value)
        ]

        let merged = EditController.mergeEntries(existing: existing, imported: imported)

        #expect(merged.map(\.id) == [bId, aId])
        #expect(merged.map(\.content) == ["b2", "a2"])
    }

    @Test("A child of a re-identified parent follows the parent")
    func childFollowsRemappedParent() throws {
        let parentId = try #require(UUID(uuidString: "C3000000-0000-4000-8000-000000000001"))
        let childId = try #require(UUID(uuidString: "C3000000-0000-4000-8000-000000000002"))
        let existing = [
            RuleEntryModel.fixture(id: parentId, name: "Group", kind: .group),
            RuleEntryModel.fixture(id: childId, name: "Leaf", kind: .value, parentId: parentId)
        ]
        let imported = [
            RuleEntryModel.fixture(id: parentId, name: "Group", kind: .group),
            RuleEntryModel.fixture(id: childId, name: "Leaf", content: "new", kind: .value, parentId: parentId)
        ]

        let merged = EditController.mergeEntries(existing: existing, imported: imported)

        #expect(merged.map(\.id) == [parentId, childId])
        #expect(merged[1].parentId == parentId)
        #expect(merged[1].content == "new")
    }

    @Test("The player export drops the Foundry source payload but keeps the entries")
    func playerExportDropsSourcePayload() async throws {
        let root = RuleRootModel.testRoot()
        let ruleId = UUID()
        let rule = RuleModel.fixture(
            id: ruleId,
            name: "Shield",
            entries: [.fixture(name: "Duration", content: "One turn")],
            sourcePayload: .foundryDocument(.object(["_id": .string("secret")]))
        )
        root.itemController.replace(model: rule, isInsert: true)

        let data = try #require(try root.exportController.playerExportData(for: ruleId))
        let decoded = try JSONCoding.decoder.decode(RuleModel.self, from: data)

        #expect(decoded.sourcePayload == nil)
        #expect(decoded.entries.map(\.content) == ["One turn"])
        #expect(rule.sourcePayload != nil, "the stored rule keeps its payload")
    }
}
#endif
