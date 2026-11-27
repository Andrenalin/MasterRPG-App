// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import Testing

@testable import RolePlayGameKit

@MainActor
@Suite("Foundry VTT value hierarchy")
struct FoundryVTTDomainMapperValueHierarchyTests {
    @Test("Nested actor values become deterministic atomic auxiliary groups")
    func mapsNestedActorValuesIntoGroups() async throws {
        // Given
        let sourceScopeId = try #require(
            UUID(uuidString: "AF71F6B2-B421-4126-BD7E-1350322BCBBD")
        )
        let package = makePackage()

        // When
        let first = try await map(package, sourceScopeId: sourceScopeId)
        let repeated = try await map(package, sourceScopeId: sourceScopeId)
        let hierarchy = try projectedHierarchy(in: first)
        let repeatedHierarchy = try projectedHierarchy(in: repeated)

        // Then
        #expect(hierarchy.rootItem.decisionOwnerId == nil)
        #expect(hierarchy.root.entries.map(\.name) == ["attributes", "literal.key"])
        #expect(hierarchy.attributesEntry.valueId == hierarchy.attributes.id)
        #expect(hierarchy.attributes.displayState == DisplayStateMask.groupHidden.rawValue)
        #expect(hierarchy.attributes.groupId == hierarchy.root.id)
        #expect(hierarchy.attributesItem.isAuxiliary)
        #expect(hierarchy.attributesItem.decisionOwnerId == hierarchy.root.id)

        #expect(hierarchy.attributes.entries.map(\.name) == ["body"])
        #expect(hierarchy.bodyEntry.valueId == hierarchy.body.id)
        #expect(hierarchy.body.displayState == DisplayStateMask.groupHidden.rawValue)
        #expect(hierarchy.body.groupId == hierarchy.attributes.id)
        #expect(hierarchy.bodyItem.isAuxiliary)
        #expect(hierarchy.bodyItem.decisionOwnerId == hierarchy.root.id)

        #expect(hierarchy.body.entries.count == 1)
        #expect(hierarchy.base.name == "base")
        #expect(hierarchy.base.type == .number)
        #expect(hierarchy.base.value == "5")
        #expect(hierarchy.base.valueId == nil)

        let literal = try #require(hierarchy.root.entries.first { $0.name == "literal.key" })
        #expect(literal.type == .text)
        #expect(literal.value == "kept as one field")
        #expect(literal.valueId == nil)

        #expect(repeatedHierarchy.root.id == hierarchy.root.id)
        #expect(repeatedHierarchy.attributes.id == hierarchy.attributes.id)
        #expect(repeatedHierarchy.body.id == hierarchy.body.id)
        #expect(repeatedHierarchy.attributesEntry.id == hierarchy.attributesEntry.id)
        #expect(repeatedHierarchy.bodyEntry.id == hierarchy.bodyEntry.id)
        #expect(repeatedHierarchy.base.id == hierarchy.base.id)

        let session = ExternalImportReviewSession(batch: first.batch)
        #expect(session.decision(for: hierarchy.rootItem) == .merge)
        #expect(session.decision(for: hierarchy.attributesItem) == .merge)
        #expect(session.decision(for: hierarchy.bodyItem) == .merge)

        session.setDecision(.skip, for: hierarchy.rootItem)
        #expect(session.decision(for: hierarchy.rootItem) == .skip)
        #expect(session.decision(for: hierarchy.attributesItem) == .skip)
        #expect(session.decision(for: hierarchy.bodyItem) == .skip)

        session.setDecision(.replace, for: hierarchy.bodyItem)
        #expect(session.decision(for: hierarchy.rootItem) == .replace)
        #expect(session.decision(for: hierarchy.attributesItem) == .replace)
        #expect(session.decision(for: hierarchy.bodyItem) == .replace)
    }
}

private extension FoundryVTTDomainMapperValueHierarchyTests {
    struct ProjectedHierarchy {
        let rootItem: ExternalImportBatchItem
        let root: ValueModel
        let attributesEntry: ValueEntryModel
        let attributesItem: ExternalImportBatchItem
        let attributes: ValueModel
        let bodyEntry: ValueEntryModel
        let bodyItem: ExternalImportBatchItem
        let body: ValueModel
        let base: ValueEntryModel
    }

    func map(
        _ package: FoundryVTTImportPackage,
        sourceScopeId: UUID
    ) async throws -> FoundryMappedImport {
        try await FoundryVTTDomainMapper().map(
            package: package,
            sourceUrl: URL(filePath: "/tmp/foundry-value-hierarchy-test.json"),
            sourceScopeId: sourceScopeId,
            selectedCategories: [.actors],
            resourceLoader: { _ in Data() }
        )
    }

    func projectedHierarchy(in mapped: FoundryMappedImport) throws -> ProjectedHierarchy {
        let rootItem = try #require(mapped.batch.items.first {
            $0.module == .value && !$0.isAuxiliary && $0.name == "Sentinel"
        })
        let root = try #require(rootItem.model as? ValueModel)
        let attributesEntry = try #require(root.entries.first { $0.name == "attributes" })
        let attributesID = try #require(attributesEntry.valueId)
        let attributesItem = try #require(mapped.batch.items.first {
            $0.module == .value && $0.id == attributesID
        })
        let attributes = try #require(attributesItem.model as? ValueModel)
        let bodyEntry = try #require(attributes.entries.first { $0.name == "body" })
        let bodyID = try #require(bodyEntry.valueId)
        let bodyItem = try #require(mapped.batch.items.first {
            $0.module == .value && $0.id == bodyID
        })
        let body = try #require(bodyItem.model as? ValueModel)
        let base = try #require(body.entries.first { $0.name == "base" })

        return ProjectedHierarchy(
            rootItem: rootItem,
            root: root,
            attributesEntry: attributesEntry,
            attributesItem: attributesItem,
            attributes: attributes,
            bodyEntry: bodyEntry,
            bodyItem: bodyItem,
            body: body,
            base: base
        )
    }

    func makePackage() -> FoundryVTTImportPackage {
        let actor = FoundryDocument(
            id: "actors/Actor/sentinel",
            documentId: "sentinel",
            documentType: .actor,
            subtype: "character",
            name: "Sentinel",
            folderId: nil,
            sort: 0,
            imagePath: nil,
            descriptionHTML: nil,
            parentId: nil,
            embeddedDocuments: [],
            references: [],
            unknownFieldNames: [],
            rawData: .object([
                "_id": .string("sentinel"),
                "name": .string("Sentinel"),
                "type": .string("character"),
                "system": .object([
                    "attributes": .object([
                        "body": .object([
                            "base": .integer(5),
                        ]),
                    ]),
                    "literal.key": .string("kept as one field"),
                ]),
            ])
        )
        return FoundryVTTImportPackage(
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: [FoundryDocumentCollection(
                id: "actors",
                name: "actors",
                label: "Actors",
                sourcePath: "data/actors",
                declaredDocumentType: .actor,
                documents: [actor],
                folders: []
            )],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 1,
                topLevelDocumentCount: 1,
                embeddedDocumentCount: 0,
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [FoundryDocumentType.actor.rawValue: 1]
            )
        )
    }
}
