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
        let entryID = try #require(UUID(uuidString: "97668F6B-439D-4AE6-8864-C24C2652DE7B"))
        let parentID = try #require(UUID(uuidString: "F78AE915-1CE4-46E9-A89C-B4A18D6F0519"))
        let rawData: FoundryJSONValue = .object([
            "integer": .integer(-4),
            "unsigned": .unsignedInteger(9),
            "number": .number(2.5)
        ])
        let metadata = RuleSourceMetadata(
            sourceIdentifier: "source-id",
            systemID: "ds4",
            systemTitle: "Dungeon Slayers 4",
            systemVersion: "4.2",
            packageIdentifier: "ds4.talents",
            packageName: "Talents",
            documentID: "talent-id",
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
                    id: entryID,
                    name: "Effect",
                    content: "Gain +1 attack.",
                    kind: .effect,
                    displayState: 1
                )
            ],
            sourceMetadata: metadata,
            sourcePayload: .foundryDocument(rawData),
            parentId: parentID
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
        #expect(decoded.parentId == parentID)
    }

    @Test("Duplicate creates independent rule and section identities")
    func duplicate() throws {
        // Given
        let firstID = try #require(UUID(uuidString: "3025168D-9B9D-43B0-824A-8AE7C6D52FCF"))
        let secondID = try #require(UUID(uuidString: "80738AEF-F2D8-4490-8070-710EBC765291"))
        let model = RuleModel.fixture(entries: [
            .fixture(id: firstID, name: "One", content: "First", kind: .text),
            .fixture(id: secondID, name: "Two", content: "Second", kind: .value)
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
