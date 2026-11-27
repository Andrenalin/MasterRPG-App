// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import RuleRPG

@Suite("Rule model")
@MainActor
struct RuleModelTests {
    @Test("Codable round trips CRDT content and Foundry source data")
    func codableRoundTrip() throws {
        // Given
        let entryId = try #require(UUID(uuidString: "97668F6B-439D-4AE6-8864-C24C2652DE7B"))
        let entryParentID = try #require(UUID(uuidString: "6CBFB184-B779-4B77-A4FB-D64BBEBA5E77"))
        let parentId = try #require(UUID(uuidString: "F78AE915-1CE4-46E9-A89C-B4A18D6F0519"))
        let rawData: FoundryJSONValue = .object([
            "integer": .integer(-4),
            "unsigned": .unsignedInteger(9),
            "number": .number(2.5)
        ])
        let metadata = RuleSourceMetadata(
            sourceIdentifier: "source-id",
            systemId: "ds4",
            systemTitle: "Dungeon Slayers 4",
            systemVersion: "4.2",
            packageIdentifier: "ds4.talents",
            packageName: "Talents",
            documentId: "talent-id",
            documentType: "Item",
            subtype: "talent",
            ruleCategory: "talent",
            imagePath: "icons/talent.webp"
        )
        let model = RuleModel.fixture(
            name: "Battle Focus",
            description: "Gain focus.",
            tags: ["talent", "martial"],
            displayState: 4,
            entries: [
                RuleEntryModel(
                    id: entryId,
                    name: "Effect",
                    content: "Gain +1 attack.",
                    kind: .effect,
                    displayState: 1,
                    parentId: entryParentID
                )
            ],
            sourceMetadata: metadata,
            sourcePayload: .foundryDocument(rawData),
            parentId: parentId
        )

        // When
        let data = try JSONEncoder().encode(model)
        let decoded = try JSONDecoder().decode(RuleModel.self, from: data)

        // Then
        #expect(decoded == model)
        #expect(decoded.sourceMetadata == metadata)
        #expect(decoded.sourcePayload == .foundryDocument(rawData))
        #expect(decoded.entries.first?.kind == .effect)
        #expect(decoded.entries.first?.displayState == 1)
        #expect(decoded.entries.first?.parentId == entryParentID)
        #expect(decoded.parentId == parentId)
    }

    @Test("Rule entries decode legacy payloads without a parent identifier")
    func legacyEntryCodable() throws {
        // Given
        let entry = RuleEntryModel.fixture(parentId: UUID())
        let currentData = try JSONEncoder().encode(entry)
        var legacyObject = try #require(
            JSONSerialization.jsonObject(with: currentData) as? [String: Any]
        )
        legacyObject.removeValue(forKey: "parentId")
        let legacyData = try JSONSerialization.data(withJSONObject: legacyObject)

        // When
        let decoded = try JSONDecoder().decode(RuleEntryModel.self, from: legacyData)

        // Then
        #expect(decoded.id == entry.id)
        #expect(decoded.name == entry.name)
        #expect(decoded.content == entry.content)
        #expect(decoded.kind == entry.kind)
        #expect(decoded.displayState == entry.displayState)
        #expect(decoded.parentId == nil)
    }

    @Test("Duplicate creates independent rule and section identities")
    func duplicate() throws {
        // Given
        let firstID = try #require(UUID(uuidString: "3025168D-9B9D-43B0-824A-8AE7C6D52FCF"))
        let secondID = try #require(UUID(uuidString: "80738AEF-F2D8-4490-8070-710EBC765291"))
        let model = RuleModel.fixture(entries: [
            .fixture(id: firstID, name: "Attributes", content: "", kind: .group),
            .fixture(
                id: secondID,
                name: "Base",
                content: "5",
                kind: .value,
                parentId: firstID
            )
        ])

        // When
        let duplicate = model.duplicate()

        // Then
        #expect(duplicate.id != model.id)
        #expect(duplicate.name == "\(model.name) Copy")
        #expect(duplicate.description == model.description)
        #expect(duplicate.tags == model.tags)
        #expect(duplicate.sourceMetadata == model.sourceMetadata)
        #expect(duplicate.sourcePayload == model.sourcePayload)
        #expect(duplicate.entries.map(\.name) == model.entries.map(\.name))
        #expect(Set(duplicate.entries.map(\.id)).isDisjoint(with: model.entries.map(\.id)))
        #expect(duplicate.entries[0].kind == .group)
        #expect(duplicate.entries[0].parentId == nil)
        #expect(duplicate.entries[1].parentId == duplicate.entries[0].id)
        #expect(duplicate.entries[1].parentId != firstID)
    }

    @Test("Entry merging preserves stable identity and safely remaps hierarchy fallbacks")
    func entryHierarchyMerge() throws {
        // Given
        let existingAttributesID = try #require(
            UUID(uuidString: "8DB96EAA-A3D5-4A26-AD89-2CD61D66421D")
        )
        let existingBodyID = try #require(
            UUID(uuidString: "4329AE12-E1F4-43CC-9822-FEA153D77D75")
        )
        let existingBaseID = try #require(
            UUID(uuidString: "3EF54F2B-C191-4333-AAD0-51708605CA55")
        )
        let importedAttributesID = try #require(
            UUID(uuidString: "AD8A6686-7860-449B-89F7-DF744AFB4BEF")
        )
        let importedBodyID = try #require(
            UUID(uuidString: "447288EA-516A-435B-ACD9-D93F434A341D")
        )
        let importedBaseID = try #require(
            UUID(uuidString: "D046474E-B1DD-4A40-863D-6438C8CDAB6C")
        )
        let existing = [
            RuleEntryModel.fixture(
                id: existingAttributesID,
                name: "attributes",
                content: "",
                kind: .group
            ),
            RuleEntryModel.fixture(
                id: existingBodyID,
                name: "body",
                content: "",
                kind: .group,
                parentId: existingAttributesID
            ),
            RuleEntryModel.fixture(
                id: existingBaseID,
                name: "base",
                content: "4",
                kind: .value,
                parentId: existingBodyID
            )
        ]
        let imported = [
            RuleEntryModel.fixture(
                id: importedAttributesID,
                name: "attributes",
                content: "",
                kind: .group
            ),
            RuleEntryModel.fixture(
                id: importedBodyID,
                name: "body",
                content: "",
                kind: .group,
                parentId: importedAttributesID
            ),
            RuleEntryModel.fixture(
                id: importedBaseID,
                name: "base",
                content: "5",
                kind: .value,
                parentId: importedBodyID
            )
        ]

        // When
        let merged = EditController.mergeEntries(existing: existing, imported: imported)

        // Then
        #expect(merged.map(\.id) == [existingAttributesID, existingBodyID, existingBaseID])
        #expect(merged.map(\.parentId) == [nil, existingAttributesID, existingBodyID])
        #expect(merged[2].content == "5")
    }

    @Test("Ambiguous hierarchy fallback does not overwrite an arbitrary entry")
    func ambiguousEntryFallback() throws {
        // Given
        let firstID = try #require(UUID(uuidString: "A34F8C63-F565-4991-A6C5-042243A29207"))
        let secondID = try #require(UUID(uuidString: "EA646B89-173B-427F-BDCE-324A08A473BB"))
        let importedID = try #require(UUID(uuidString: "6137AE4B-9226-4BA0-874F-580578978B46"))
        let existing = [
            RuleEntryModel.fixture(id: firstID, name: "base", kind: .value),
            RuleEntryModel.fixture(id: secondID, name: "base", kind: .value)
        ]
        let imported = [
            RuleEntryModel.fixture(id: importedID, name: "base", content: "new", kind: .value)
        ]

        // When
        let merged = EditController.mergeEntries(existing: existing, imported: imported)

        // Then
        #expect(merged.map(\.id) == [importedID])
        #expect(merged[0].content == "new")
    }

    /// CODE_AUDIT_Since_3.0.1 §5.1: the name fallback compares names without link markup.
    @Test("A name that only gained a link keeps its entry")
    func linkedNameFallback() throws {
        // Given
        let existingID = try #require(UUID(uuidString: "0B4E6C1F-3E0D-4C5B-9F60-7D2A1E8C4B11"))
        let importedID = try #require(UUID(uuidString: "5C9A2D47-8B1E-4F3A-A6D2-0E7B3C9F1A22"))
        let linkedName = "[Goblin](RPG://table/0/\(UUID().uuidString)) Den"
        let existing = [RuleEntryModel.fixture(id: existingID, name: "Goblin Den", kind: .value)]
        let imported = [RuleEntryModel.fixture(id: importedID, name: linkedName, content: "new", kind: .value)]

        // When
        let merged = EditController.mergeEntries(existing: existing, imported: imported)

        // Then
        #expect(merged.map(\.id) == [existingID])
        #expect(merged[0].name == linkedName)
        #expect(merged[0].content == "new")
    }

    /// CODE_AUDIT_26 §5.43: a new "Notes" dragged above the existing "Notes" must not take the
    /// existing entry's identity and leave the existing entry in the result a second time.
    @Test("A new entry listed before a same-named existing one keeps ids unique")
    func reorderedNewEntryDoesNotDuplicateIds() throws {
        // Given
        let existingID = try #require(UUID(uuidString: "3D1C7B52-0A44-4E0B-8E8D-4F6B2C7A9D10"))
        let newID = try #require(UUID(uuidString: "9E2F5A61-7B3C-4D88-A1F0-5C6D7E8F9A21"))
        let existing = [RuleEntryModel.fixture(id: existingID, name: "Notes", content: "old", kind: .value)]
        let imported = [
            RuleEntryModel.fixture(id: newID, name: "Notes", content: "new", kind: .value),
            RuleEntryModel.fixture(id: existingID, name: "Notes", content: "old", kind: .value)
        ]

        // When
        let merged = EditController.mergeEntries(existing: existing, imported: imported)

        // Then
        #expect(merged.map(\.id) == [newID, existingID])
        #expect(Set(merged.map(\.id)).count == merged.count)
        #expect(merged.map(\.content) == ["new", "old"])
    }

    @Test("Stable versions and localized search include source metadata and sections")
    func versionAndFiltering() {
        // Given
        let model = RuleModel.fixture(
            name: "Arcane Shield",
            description: "Protective magic",
            entries: [.fixture(name: "Duration", content: "Until next turn")],
            sourceMetadata: RuleSourceMetadata(systemTitle: "Dungeon Slayers", packageName: "Spells")
        )
        let copy = model.copy()
        let initialVersion = model.version

        // When
        copy.entries[0].content = "One minute"

        // Then
        #expect(initialVersion == model.version)
        #expect(copy.version != model.version)
        #expect(model.filter(filter: "arcane", includeEntries: false))
        #expect(model.filter(filter: "dungeon", includeEntries: false))
        #expect(model.filter(filter: "next turn", includeEntries: true))
        #expect(!model.filter(filter: "next turn", includeEntries: false))
        #expect(!model.filter(filter: "missing", includeEntries: true))
    }
}
#endif
