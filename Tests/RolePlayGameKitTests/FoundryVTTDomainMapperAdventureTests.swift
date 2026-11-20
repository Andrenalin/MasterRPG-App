// @copyright André Trettin

import AdventureRPG
import CoreRPG
import Foundation
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT §5.4: an Adventure links the item each embedded document is projected to, not the
/// helper models recorded under the same source id, and in a fixed order.
@MainActor
@Suite("Foundry VTT adventure mapping")
struct FoundryVTTDomainMapperAdventureTests {
    @Test("An Adventure gets one entry per embedded document and links no hidden field group")
    func linksOnlyTheProjectedItems() async throws {
        // Given
        let mapped = try await map(makePackage())

        // When
        let adventureItem = try #require(mapped.batch.items.first { $0.module == .adventure })
        let adventure = try #require(adventureItem.model as? AdventureModel)
        let sentinel = try #require(mapped.batch.items.first {
            $0.module == .value && !$0.isAuxiliary && $0.name == "Sentinel"
        })
        let sword = try #require(mapped.batch.items.first {
            $0.module == .rule && $0.name == "Sword"
        })

        // Then
        #expect(adventure.entries.map(\.name) == ["Sentinel", "Sword"], "one entry per embedded document, in document order")
        #expect(links(adventure.entries[0].content, to: sentinel.id))
        #expect(links(adventure.entries[1].content, to: sword.id), "an Item is linked once, to the destination links in imported text resolve to")

        let auxiliaryIds = mapped.batch.items.filter(\.isAuxiliary).map(\.id)
        #expect(!auxiliaryIds.isEmpty, "the fixture must have hidden field groups, or the test proves nothing")
        for entry in adventure.entries {
            for auxiliaryId in auxiliaryIds {
                #expect(!links(entry.content, to: auxiliaryId), "a hidden field group must not be linked from the Adventure")
            }
        }
    }

    @Test("The Adventure entries are the same on every import")
    func entriesAreDeterministic() async throws {
        let package = makePackage()
        var contents: [[String]] = []
        for _ in 0..<5 {
            let mapped = try await map(package)
            let adventureItem = try #require(mapped.batch.items.first { $0.module == .adventure })
            let adventure = try #require(adventureItem.model as? AdventureModel)
            contents.append(adventure.entries.map(\.content))
        }

        #expect(Set(contents.map { $0.joined(separator: "\n") }).count == 1)
    }
}

private extension FoundryVTTDomainMapperAdventureTests {
    func links(_ content: String, to id: UUID) -> Bool {
        content.lowercased().contains(id.uuidString.lowercased())
    }

    func map(_ package: FoundryVTTImportPackage) async throws -> FoundryMappedImport {
        try await FoundryVTTDomainMapper().map(
            package: package,
            sourceURL: URL(filePath: "/tmp/foundry-adventure-test.json"),
            sourceScopeID: try #require(UUID(uuidString: "5C0B1A57-3F3E-4D0B-9B52-0E3B8F6F2A11")),
            selectedCategories: [.adventures, .actors, .items, .rules],
            resourceLoader: { _ in Data() }
        )
    }

    func document(
        id: String,
        type: FoundryDocumentType,
        subtype: String? = nil,
        name: String,
        parentID: String?,
        embedded: [FoundryDocument] = [],
        system: FoundryJSONValue? = nil
    ) -> FoundryDocument {
        var raw: [String: FoundryJSONValue] = [
            "_id": .string(id),
            "name": .string(name)
        ]
        if let subtype { raw["type"] = .string(subtype) }
        if let system { raw["system"] = system }
        return FoundryDocument(
            id: "adventures/\(type.rawValue)/\(id)",
            documentID: id,
            documentType: type,
            subtype: subtype,
            name: name,
            folderID: nil,
            sort: 0,
            imagePath: nil,
            descriptionHTML: nil,
            parentID: parentID,
            embeddedDocuments: embedded,
            references: [],
            unknownFieldNames: [],
            rawData: .object(raw)
        )
    }

    func makePackage() -> FoundryVTTImportPackage {
        let adventureId = "adventures/Adventure/crypt"
        // Nested `system` objects become hidden field-group models recorded under the Actor's id.
        let actor = document(
            id: "sentinel",
            type: .actor,
            subtype: "character",
            name: "Sentinel",
            parentID: adventureId,
            system: .object([
                "attributes": .object(["body": .object(["base": .integer(5)])]),
                "skills": .object(["stealth": .object(["rank": .integer(2)])])
            ])
        )
        let item = document(id: "sword", type: .item, subtype: "weapon", name: "Sword", parentID: adventureId)
        let adventure = FoundryDocument(
            id: adventureId,
            documentID: "crypt",
            documentType: .adventure,
            subtype: nil,
            name: "The Crypt",
            folderID: nil,
            sort: 0,
            imagePath: nil,
            descriptionHTML: nil,
            parentID: nil,
            embeddedDocuments: [actor, item],
            references: [],
            unknownFieldNames: [],
            rawData: .object(["_id": .string("crypt"), "name": .string("The Crypt")])
        )
        return FoundryVTTImportPackage(
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: [FoundryDocumentCollection(
                id: "adventures",
                name: "adventures",
                label: "Adventures",
                sourcePath: "data/adventures",
                declaredDocumentType: .adventure,
                documents: [adventure],
                folders: []
            )],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 1,
                topLevelDocumentCount: 1,
                embeddedDocumentCount: 2,
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [FoundryDocumentType.adventure.rawValue: 1]
            )
        )
    }
}
