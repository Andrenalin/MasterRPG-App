// @copyright André Trettin

#if canImport(Testing)
import CoreRPG
import Foundation
import Testing

@testable import RuleRPG

@Suite("Foundry rule mapping")
@MainActor
struct RuleFoundryFactoryTests {
    @Test("Typed Foundry rules retain provenance and their lossless payload")
    func typedRuleMapping() throws {
        // Given
        let manifest = foundryManifest()
        let rule = foundryRule()
        let modelID = try #require(UUID(uuidString: "01877D15-01FC-4ED0-9E63-2D319BF0D842"))
        let parentID = try #require(UUID(uuidString: "668D0D89-AAB9-49F9-A3B4-B8BA8FF29D9B"))

        // When
        let model = RuleModel.foundry(
            rule,
            manifest: manifest,
            id: modelID,
            identityNamespace: "world.ds4.spells",
            parentId: parentID
        )

        // Then
        #expect(model.id == modelID)
        #expect(model.parentId == parentID)
        #expect(model.name == "Arcane Shield")
        #expect(model.description.contains("Shield & ward"))
        #expect(!model.description.contains("<p>"))
        #expect(model.tags == ["Magic", "spell", "Dungeon Slayers 4", "Foundry VTT"])
        #expect(model.sourceMetadata.sourceIdentifier == rule.id)
        #expect(model.sourceMetadata.systemID == "ds4")
        #expect(model.sourceMetadata.systemTitle == "Dungeon Slayers 4")
        #expect(model.sourceMetadata.systemVersion == "4.2")
        #expect(model.sourceMetadata.packageIdentifier == "ds4.spells")
        #expect(model.sourceMetadata.documentID == "arcane-shield")
        #expect(model.sourceMetadata.subtype == "spell")
        #expect(model.sourceMetadata.imagePath == "icons/arcane-shield.webp")
        #expect(model.sourcePayload == .foundryRule(rule))
        #expect(model.entries.map(\.kind) == [.value, .reference, .embeddedRule, .effect])
        #expect(model.entries[0].name == "system.cost")
        #expect(model.entries[0].content == "2")
        #expect(model.entries[1].content.contains("Compendium.ds4.spells.Item.fireball"))
        #expect(model.entries[2].content.contains("Embedded ward"))
        #expect(model.entries[2].content.contains("Embedded Reference"))
        #expect(model.entries[2].content.contains("Compendium.ds4.spells.Item.fireball"))
        #expect(model.entries[2].content.contains("Embedded Effect"))
        #expect(model.entries[2].content.contains("system.armor"))
        #expect(model.entries[2].content.contains("mode 5, priority 20"))
        #expect(model.entries[3].content.contains("system.defense"))
        #expect(model.entries[3].content.contains("mode 2, priority 10"))
    }

    @Test("Identity namespaces deterministically scope generated entry UUIDs")
    func scopedEntryIdentity() {
        // Given
        let manifest = foundryManifest()
        let rule = foundryRule()

        // When
        let first = RuleModel.foundry(rule, manifest: manifest, identityNamespace: "package-a")
        let repeated = RuleModel.foundry(rule, manifest: manifest, identityNamespace: "package-a")
        let otherPackage = RuleModel.foundry(rule, manifest: manifest, identityNamespace: "package-b")

        // Then
        #expect(first.id == rule.masterRPGID)
        #expect(repeated.id == rule.masterRPGID)
        #expect(first.entries.map(\.id) == repeated.entries.map(\.id))
        #expect(zip(first.entries, otherPackage.entries).allSatisfy { pair in
            pair.0.id != pair.1.id
        })
        #expect(first.sourceMetadata.sourceIdentifier == rule.id)
        #expect(otherPackage.sourceMetadata.sourceIdentifier == rule.id)
    }

    @Test("Generic Foundry documents flatten editable values and retain raw JSON")
    func genericDocumentMapping() throws {
        // Given
        let modelID = try #require(UUID(uuidString: "7EC9760C-8395-4F9B-A32E-36585FA5363F"))
        let rawData: FoundryJSONValue = .object([
            "_id": .string("talent-1"),
            "type": .string("talent"),
            "img": .string("icons/talent.webp"),
            "_stats": .object([
                "systemId": .string("ds4"),
                "systemVersion": .string("4.2")
            ]),
            "system": .object([
                "cost": .integer(3),
                "enabled": .bool(true),
                "choices": .array([.string("one"), .string("two")])
            ])
        ])

        // When
        let model = RuleModel.foundryDocument(
            id: modelID,
            name: "Battle Focus",
            descriptionHTML: "<p>Gain &lt;focus&gt;.</p>",
            tags: ["talent", "martial"],
            documentType: "Item",
            subtype: "talent",
            rawData: rawData,
            parentId: nil,
            packageIdentifier: "world.ds4",
            identityNamespace: "world.ds4.Item.talent-1"
        )

        // Then
        #expect(model.description == "Gain <focus>.")
        #expect(model.sourceMetadata.sourceIdentifier == "talent-1")
        #expect(model.sourceMetadata.systemID == "ds4")
        #expect(model.sourceMetadata.systemVersion == "4.2")
        #expect(model.sourceMetadata.packageIdentifier == "world.ds4")
        #expect(model.sourceMetadata.ruleCategory == "talent")
        #expect(model.sourcePayload == .foundryDocument(rawData))
        #expect(model.entries.map(\.name) == ["choices.0", "choices.1", "cost", "enabled"])
        #expect(model.entries.map(\.content) == ["one", "two", "3", "true"])
        #expect(model.entries.allSatisfy { $0.kind == .value })
    }
}

private func foundryManifest() -> FoundrySystemManifest {
    FoundrySystemManifest(
        id: "ds4",
        title: "Dungeon Slayers 4",
        description: "A test manifest",
        version: "4.2",
        compatibility: FoundryCompatibility(minimum: "12", verified: "13", maximum: nil),
        packs: [],
        rawData: .object(["id": .string("ds4")])
    )
}

private func foundryRule() -> FoundryRuleDefinition {
    FoundryRuleDefinition(
        id: "Compendium.ds4.spells.Item.arcane-shield",
        documentID: "arcane-shield",
        packName: "spells",
        documentType: "Item",
        subtype: "spell",
        category: .spell,
        name: "Arcane Shield",
        descriptionHTML: "<p>Shield &amp; ward</p>",
        imagePath: "icons/arcane-shield.webp",
        folderID: "defense",
        values: [FoundryRuleValue(path: "system.cost", value: .integer(2))],
        tags: ["Magic", "spell"],
        references: [
            FoundryRuleReference(
                kind: .compendium,
                sourcePath: "system.related",
                rawToken: "@UUID[Compendium.ds4.spells.Item.fireball]",
                target: "Compendium.ds4.spells.Item.fireball",
                label: "Fireball",
                packName: "spells",
                documentID: "fireball"
            )
        ],
        embeddedRules: [
            FoundryEmbeddedRule(
                id: "embedded-ward",
                name: "Embedded Ward",
                subtype: "talent",
                category: .talent,
                descriptionHTML: "<p>Embedded ward</p>",
                imagePath: nil,
                values: [FoundryRuleValue(path: "system.bonus", value: .integer(1))],
                references: [FoundryRuleReference(
                    kind: .uuid,
                    sourcePath: "system.embedded.related",
                    rawToken: "@UUID[Compendium.ds4.spells.Item.fireball]{Embedded Reference}",
                    target: "Compendium.ds4.spells.Item.fireball",
                    label: "Embedded Reference",
                    packName: "spells",
                    documentID: "fireball"
                )],
                effects: [FoundryRuleEffect(
                    id: "embedded-effect",
                    name: "Embedded Effect",
                    isDisabled: true,
                    transfersToActor: false,
                    statuses: ["armored"],
                    changes: [FoundryRuleEffectChange(
                        path: "system.armor",
                        mode: 5,
                        operand: .integer(3),
                        priority: 20
                    )],
                    duration: .object(["rounds": .integer(2)]),
                    rawData: .object(["_id": .string("embedded-effect")])
                )],
                rawData: .object(["_id": .string("embedded-ward")])
            )
        ],
        effects: [
            FoundryRuleEffect(
                id: "effect-defense",
                name: "Defense Bonus",
                isDisabled: false,
                transfersToActor: true,
                statuses: ["guarded"],
                changes: [
                    FoundryRuleEffectChange(
                        path: "system.defense",
                        mode: 2,
                        operand: .integer(2),
                        priority: 10
                    )
                ],
                duration: .object(["rounds": .integer(1)]),
                rawData: .object(["_id": .string("effect-defense")])
            )
        ],
        rawData: .object([
            "_id": .string("arcane-shield"),
            "system": .object(["cost": .integer(2)])
        ])
    )
}
#endif
