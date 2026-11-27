// @copyright André Trettin

import CoreRPG
import Foundation
import RuleRPG
import RPGResourcesDebug
import Testing

@testable import RolePlayGameKit

@MainActor
@Suite("Foundry VTT rule projection")
struct FoundryVTTDomainMapperRuleTests {
    @Test("A normalized system package becomes a scoped editable rule hierarchy")
    func mapsNormalizedRules() async throws {
        // Given
        let sourceScopeId = try #require(
            UUID(uuidString: "6F31C08D-C408-4631-B1C0-A3E31962C646")
        )
        let fixture = makePackage()

        // When
        let first = try await map(fixture.package, sourceScopeId: sourceScopeId)
        let repeated = try await map(fixture.package, sourceScopeId: sourceScopeId)
        let rule = try #require(first.batch.items.compactMap { $0.model as? RuleModel }
            .first { $0.category != .folder })

        // Then
        let sourceNamespace = "external-source:\(sourceScopeId.uuidString.lowercased())"
        let expectedRuleID = FoundryRuleIdentity.uuid(
            for: "\(sourceNamespace)#rule#\(fixture.rule.id)"
        )
        let expectedFolderID = FoundryRuleIdentity.uuid(
            for: "\(sourceNamespace)#rules#pack#core-rules#folder#combat"
        )
        #expect(rule.id == expectedRuleID)
        #expect(rule.parentId == expectedFolderID)
        #expect(rule.sourceMetadata.systemId == "test-system")
        #expect(rule.sourceMetadata.packageName == "core-rules")
        let retainedPayload: FoundryRuleDefinition? = if case .foundryRule(let value)? = rule.sourcePayload {
            value
        } else {
            nil
        }
        let retainedRule = try #require(retainedPayload)
        #expect(retainedRule.name == fixture.rule.name)
        #expect(retainedRule.rawData["ownership"] == nil)
        let damage = try #require(rule.entries.first {
            $0.name == "damage" && $0.kind == .value
        })
        #expect(damage.content == "4")
        #expect(damage.parentId == nil)
        #expect(!rule.entries.contains { $0.name == "system.damage" })
        #expect(repeated.batch.items.map(\.id) == first.batch.items.map(\.id))

        let folders = first.batch.items.compactMap { $0.model as? RuleModel }
            .filter { $0.category == .folder }
        let systemFolder = try #require(folders.first { $0.name == "Test System" })
        let packFolder = try #require(folders.first { $0.name == "Core Rules" })
        let combatFolder = try #require(folders.first { $0.name == "Combat" })
        #expect(packFolder.parentId == systemFolder.id)
        #expect(combatFolder.parentId == packFolder.id)
        #expect(first.mappings.contains { mapping in
            mapping.foundryIdentifier == fixture.rule.id
                && mapping.references.contains { $0.module == .rule && $0.itemId == rule.id }
        })
    }

    // CODE_AUDIT_28 §6.2: the factory's neutralisation was overwritten by the mapper's plain text.
    @Test("A web link and an app link in an imported description cannot become live links")
    func descriptionLinksAreInert() async throws {
        let html = "<p>[Click](https://evil.example/x) and [Item](masterrpg://item/1/\(UUID().uuidString)) and https://plain.example</p>"
        let fixture = makePackage(descriptionHTML: html)

        let mapped = try await map(fixture.package, sourceScopeId: UUID())

        let rule = try #require(mapped.batch.items.compactMap { $0.model as? RuleModel }.first { $0.category != .folder })
        #expect(!rule.description.contains("](" ))
        #expect(!rule.description.contains("://"))
        #expect(rule.description.contains("Click"))
        #expect(rule.description.contains("evil.example"))
    }

    @Test("Separate Foundry sources cannot collide in rule or entry identity")
    func scopesRuleIdentityToSource() async throws {
        // Given
        let fixture = makePackage()
        let firstScope = try #require(UUID(uuidString: "912CD1AD-8892-4592-B494-93B48E00933A"))
        let secondScope = try #require(UUID(uuidString: "322826A5-753C-46B9-8320-E7059E2168A9"))

        // When
        let first = try await map(fixture.package, sourceScopeId: firstScope)
        let second = try await map(fixture.package, sourceScopeId: secondScope)
        let firstRule = try #require(first.batch.items.compactMap { $0.model as? RuleModel }
            .first { $0.category != .folder })
        let secondRule = try #require(second.batch.items.compactMap { $0.model as? RuleModel }
            .first { $0.category != .folder })

        // Then
        #expect(firstRule.id != secondRule.id)
        #expect(Set(firstRule.entries.map(\.id)).isDisjoint(with: Set(secondRule.entries.map(\.id))))
        #expect(firstRule.sourceMetadata.sourceIdentifier == secondRule.sourceMetadata.sourceIdentifier)
    }

    @Test("Legacy and modern Foundry rule references become sanitized app links")
    func rewritesNormalizedRuleReferences() async throws {
        // Given
        let sourceScopeId = try #require(UUID(uuidString: "BE3D709E-BB7D-4D03-A6A9-292DC719ACF7"))
        let legacyTarget = "test-system.core-rules.rule-1"
        let modernTarget = "Compendium.test-system.core-rules.Item.rule-1"
        let legacyReference = FoundryRuleReference(
            kind: .compendium,
            sourcePath: "system.description",
            rawToken: "@Compendium[\(legacyTarget)]{Legacy Target}",
            target: legacyTarget,
            label: "Legacy Target",
            packName: "core-rules",
            documentId: "rule-1"
        )
        let modernReference = FoundryRuleReference(
            kind: .uuid,
            sourcePath: "system.details",
            rawToken: "@UUID[\(modernTarget)]{Modern Target}",
            target: modernTarget,
            label: "Modern Target",
            packName: "core-rules",
            documentId: "rule-1"
        )
        let embeddedEffect = FoundryRuleEffect(
            id: "embedded-effect",
            name: "Armor Bonus<script>effectNameLeak()</script>",
            isDisabled: false,
            transfersToActor: true,
            statuses: ["guarded<script>statusLeak()</script>"],
            changes: [FoundryRuleEffectChange(
                path: "system.armor",
                mode: 2,
                operand: .string("<strong>2</strong><script>operandLeak()</script>"),
                priority: 10
            )],
            duration: .object(["rounds": .integer(1)]),
            rawData: .object([:])
        )
        let embeddedRule = FoundryEmbeddedRule(
            id: "embedded-rule",
            name: "Embedded rule",
            subtype: "talent",
            category: .talent,
            descriptionHTML: "<p>Embedded details.</p><script>embeddedLeak()</script>",
            imagePath: nil,
            values: [],
            references: [modernReference],
            effects: [embeddedEffect],
            rawData: .object([:])
        )
        let fixture = makePackage(
            descriptionHTML: "<p>See @Compendium[\(legacyTarget)]{Description Target}.</p><script>descriptionLeak()</script>",
            references: [legacyReference, modernReference],
            embeddedRules: [embeddedRule]
        )

        // When
        let mapped = try await map(fixture.package, sourceScopeId: sourceScopeId)
        let rule = try #require(mapped.batch.items.compactMap { $0.model as? RuleModel }
            .first { $0.category != .folder })
        let referenceEntries = rule.entries.filter { $0.kind == .reference }
        let embeddedEntry = try #require(rule.entries.first { $0.kind == .embeddedRule })

        // Then
        let descriptionLink = try #require(LinkReplaceController.links(for: rule.description).first)
        #expect(descriptionLink.module == .rule)
        #expect(descriptionLink.itemId == rule.id)
        #expect(!rule.description.contains("descriptionLeak"))
        #expect(!rule.description.contains("@Compendium"))

        #expect(referenceEntries.count == 2)
        for entry in referenceEntries {
            let link = try #require(LinkReplaceController.links(for: entry.content).first)
            #expect(link.module == .rule)
            #expect(link.itemId == rule.id)
            #expect(!entry.content.contains("@Compendium"))
            #expect(!entry.content.contains("@UUID"))
        }

        let embeddedLink = try #require(LinkReplaceController.links(for: embeddedEntry.content).first)
        #expect(embeddedLink.module == .rule)
        #expect(embeddedLink.itemId == rule.id)
        #expect(embeddedEntry.content.contains("References"))
        #expect(embeddedEntry.content.contains("Effects"))
        #expect(embeddedEntry.content.contains("Armor Bonus"))
        #expect(embeddedEntry.content.contains("system.armor"))
        #expect(embeddedEntry.content.contains("mode 2, priority 10"))
        #expect(!embeddedEntry.content.contains("embeddedLeak"))
        #expect(!embeddedEntry.content.contains("effectNameLeak"))
        #expect(!embeddedEntry.content.contains("statusLeak"))
        #expect(!embeddedEntry.content.contains("operandLeak"))
        #expect(!embeddedEntry.content.contains("@UUID"))

        #expect(mapped.mappings.contains { $0.foundryIdentifier == legacyTarget })
        #expect(mapped.mappings.contains { $0.foundryIdentifier == modernTarget })
    }

    @Test("A world Item remains a value and also becomes an editable generic rule")
    func mapsGenericWorldItemWithoutDuplicatingNormalizedRules() async throws {
        // Given
        let sourceScopeId = try #require(UUID(uuidString: "D8938963-8D42-4A93-BA2E-B2C4CDF2B1E0"))
        let item = FoundryDocument(
            id: "items/Item/item-1",
            documentId: "item-1",
            documentType: .item,
            subtype: "weapon",
            name: "Iron Sword",
            folderId: "equipment",
            sort: 0,
            imagePath: nil,
            descriptionHTML: "<p>A dependable blade. @UUID[Item.item-1]{Read rule}.</p><script>descriptionLeak()</script>",
            parentId: nil,
            embeddedDocuments: [],
            references: [],
            unknownFieldNames: [],
            rawData: .object([
                "_id": .string("item-1"),
                "type": .string("weapon"),
                "system": .object([
                    "damage": .string("1d6"),
                    "ruleText": .string("<p>@Item[item-1]{Entry rule}</p><script>entryLeak()</script>"),
                ]),
            ])
        )
        let package = FoundryVTTImportPackage(
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: [FoundryDocumentCollection(
                id: "items",
                name: "items",
                label: "Items",
                sourcePath: "data/items",
                declaredDocumentType: .item,
                documents: [item],
                folders: [FoundryDocumentFolder(
                    id: "items/Folder/equipment",
                    documentId: "equipment",
                    name: "Equipment",
                    parentId: nil,
                    documentType: .item,
                    sort: 0,
                    rawData: .object(["_id": .string("equipment")])
                )]
            )],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 1,
                topLevelDocumentCount: 1,
                embeddedDocumentCount: 0,
                folderCount: 1,
                unknownFieldCount: 0,
                documentCounts: ["Item": 1]
            )
        )

        // When
        let mapped = try await FoundryVTTDomainMapper().map(
            package: package,
            sourceUrl: URL(filePath: "/tmp/foundry-world-test.json"),
            sourceScopeId: sourceScopeId,
            selectedCategories: [.items, .rules],
            resourceLoader: { _ in Data() }
        )
        let rule = try #require(mapped.batch.items.compactMap { $0.model as? RuleModel }
            .first { $0.category != .folder })

        // Then
        #expect(mapped.batch.items.contains { $0.module == .value && $0.name == "Iron Sword" })
        #expect(rule.name == "Iron Sword")
        #expect(rule.sourcePayload == .foundryDocument(item.rawData))
        #expect(rule.entries.contains { $0.name == "damage" && $0.content == "1d6" })
        #expect(rule.parentId != nil)
        let descriptionLink = try #require(LinkReplaceController.links(for: rule.description).first)
        #expect(descriptionLink.module == .rule)
        #expect(descriptionLink.itemId == rule.id)
        #expect(!rule.description.contains("descriptionLeak"))
        let ruleText = try #require(rule.entries.first { $0.name == "ruleText" })
        let entryLink = try #require(LinkReplaceController.links(for: ruleText.content).first)
        #expect(entryLink.module == .rule)
        #expect(entryLink.itemId == rule.id)
        #expect(!ruleText.content.contains("entryLeak"))
    }

    @Test("The supplied DungeonSlayers system package imports into RuleRPG")
    func mapsSuppliedDungeonSlayersPackage() async throws {
        // Given
        let bundle = ResourcesDebug.bundle
        let packageURL = bundle.url(forResource: ResourcesDebug.vttExample, withExtension: "zip")

        try #require(packageURL != nil)
        #expect(FileManager.default.fileExists(atPath: packageURL!.path()))

        let reader = FoundryVTTImportReader()
        let package = try await reader.read(from: packageURL!)
        let sourceScopeId = try #require(
            UUID(uuidString: "9773E23D-BB3E-463D-9CC0-15726C2D5D24")
        )

        // When
        let mapped = try await FoundryVTTDomainMapper().map(
            package: package,
            sourceUrl: packageURL!,
            sourceScopeId: sourceScopeId,
            selectedCategories: [.rules],
            resourceLoader: { resource in
                try await reader.resourceData(for: resource, from: packageURL!).data
            }
        )
        let rulePackage = try #require(package.rulePackage)
        let projectedRules = mapped.batch.items.compactMap { $0.model as? RuleModel }
            .filter { !$0.specialCategory }

        // Then
        #expect(package.kind == .system)
        #expect(package.manifest?.id == "ds4")
        #expect(rulePackage.manifest.id == "ds4")
        #expect(!rulePackage.compendiums.isEmpty)
        #expect(!projectedRules.isEmpty)
        #expect(projectedRules.count == rulePackage.ruleCount)
        #expect(Set(projectedRules.map(\.id)).count == projectedRules.count)
        #expect(projectedRules.allSatisfy { $0.sourceMetadata.systemId == "ds4" })
        #expect(projectedRules.contains { !$0.entries.isEmpty })
        #expect(projectedRules.allSatisfy { $0.sourcePayload != nil })
    }
}

private extension FoundryVTTDomainMapperRuleTests {
    struct Fixture {
        let package: FoundryVTTImportPackage
        let rule: FoundryRuleDefinition
    }

    func map(
        _ package: FoundryVTTImportPackage,
        sourceScopeId: UUID
    ) async throws -> FoundryMappedImport {
        try await FoundryVTTDomainMapper().map(
            package: package,
            sourceUrl: URL(filePath: "/tmp/foundry-rule-test.zip"),
            sourceScopeId: sourceScopeId,
            selectedCategories: [.rules],
            resourceLoader: { _ in Data() }
        )
    }

    func makePackage(
        descriptionHTML: String? = "<p>Deal additional damage.</p>",
        references: [FoundryRuleReference] = [],
        embeddedRules: [FoundryEmbeddedRule] = []
    ) -> Fixture {
        let compatibility = FoundryCompatibility(minimum: "12", verified: "13", maximum: nil)
        let pack = FoundryPackManifest(
            name: "core-rules",
            label: "Core Rules",
            path: "packs/core-rules",
            documentType: "Item",
            systemId: "test-system"
        )
        let manifest = FoundrySystemManifest(
            id: "test-system",
            title: "Test System",
            description: nil,
            version: "1.0.0",
            compatibility: compatibility,
            packs: [pack],
            rawData: .object(["id": .string("test-system")])
        )
        let rule = FoundryRuleDefinition(
            id: "core-rules.Item.rule-1",
            documentId: "rule-1",
            packName: "core-rules",
            documentType: "Item",
            subtype: "talent",
            category: .talent,
            name: "Power Strike",
            descriptionHTML: descriptionHTML,
            imagePath: "icons/power-strike.webp",
            folderId: "combat",
            values: [FoundryRuleValue(path: "system.damage", value: .integer(4))],
            tags: ["combat"],
            references: references,
            embeddedRules: embeddedRules,
            effects: [],
            rawData: .object([
                "_id": .string("rule-1"),
                "ownership": .object(["default": .integer(0)]),
                "system": .object(["damage": .integer(4)]),
            ])
        )
        let rulePackage = FoundryRulePackage(
            manifest: manifest,
            manifestPath: "system.json",
            templatePath: nil,
            templateData: nil,
            schemas: [],
            compendiums: [FoundryCompendium(
                manifest: pack,
                rules: [rule],
                folders: [FoundryFolder(id: "combat", name: "Combat", parentId: nil, sort: 0)]
            )],
            assetPaths: [],
            licensePaths: [],
            diagnostics: []
        )
        let package = FoundryVTTImportPackage(
            kind: .system,
            manifestPath: "system.json",
            manifest: FoundryVTTPackageManifest(
                kind: .system,
                id: "test-system",
                title: "Test System",
                descriptionHTML: nil,
                version: "1.0.0",
                systemId: "test-system",
                compatibility: compatibility,
                rawData: .object(["id": .string("test-system")])
            ),
            collections: [],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 0,
                topLevelDocumentCount: 0,
                embeddedDocumentCount: 0,
                folderCount: 1,
                unknownFieldCount: 0,
                documentCounts: ["Item": 1]
            ),
            rulePackage: rulePackage
        )
        return Fixture(package: package, rule: rule)
    }
}
