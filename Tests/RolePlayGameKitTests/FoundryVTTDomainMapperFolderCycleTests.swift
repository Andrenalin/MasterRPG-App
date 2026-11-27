// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT §5.5: folders that name each other as parent must not become a circular `parentId`
/// chain. The guard compared canonical ids with the raw parent id, so it never saw a cycle.
@MainActor
@Suite("Foundry VTT folder cycles")
struct FoundryVTTDomainMapperFolderCycleTests {
    @Test("Two folders naming each other are both reachable from a root")
    func twoFolderCycleIsBroken() async throws {
        let mapped = try await map(folders: [
            folder(documentId: "a", name: "Alpha", parentRawId: "b"),
            folder(documentId: "b", name: "Beta", parentRawId: "a")
        ])

        let folders = valueFolders(in: mapped)
        #expect(folders.count == 2)
        #expect(hasNoParentCycle(folders))
        #expect(folders.contains { $0.parentId == nil }, "the cycle is cut by placing one folder at the root")
    }

    @Test("A folder that is its own parent is placed at the root")
    func selfParentIsBroken() async throws {
        let mapped = try await map(folders: [folder(documentId: "a", name: "Alpha", parentRawId: "a")])

        let folders = valueFolders(in: mapped)
        #expect(folders.count == 1)
        #expect(folders.first?.parentId == nil)
    }

    @Test("A valid parent chain is kept")
    func validChainIsKept() async throws {
        let mapped = try await map(folders: [
            folder(documentId: "a", name: "Alpha", parentRawId: nil),
            folder(documentId: "b", name: "Beta", parentRawId: "a")
        ])

        let folders = valueFolders(in: mapped)
        let alpha = try #require(folders.first { $0.name == "Alpha" })
        let beta = try #require(folders.first { $0.name == "Beta" })
        #expect(beta.parentId == alpha.id)
        #expect(alpha.parentId == nil)
    }
}

private extension FoundryVTTDomainMapperFolderCycleTests {
    func valueFolders(in mapped: FoundryMappedImport) -> [ValueModel] {
        mapped.batch.items
            .filter { $0.module == .value }
            .compactMap { $0.model as? ValueModel }
            .filter { $0.category == .folder }
    }

    func hasNoParentCycle(_ folders: [ValueModel]) -> Bool {
        let parents = Dictionary(folders.map { ($0.id, $0.parentId) }, uniquingKeysWith: { first, _ in first })
        for folder in folders {
            var seen: Set<UUID> = [folder.id]
            var current = folder.parentId
            while let id = current {
                guard seen.insert(id).inserted else { return false }
                current = parents[id] ?? nil
            }
        }
        return true
    }

    func folder(documentId: String, name: String, parentRawId: String?) -> FoundryDocumentFolder {
        FoundryDocumentFolder(
            id: "actors/Folder/\(documentId)",
            documentId: documentId,
            name: name,
            parentId: parentRawId,
            documentType: .actor,
            sort: 0,
            rawData: .object(["_id": .string(documentId), "name": .string(name)])
        )
    }

    func map(folders: [FoundryDocumentFolder]) async throws -> FoundryMappedImport {
        let package = FoundryVTTImportPackage(
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: [FoundryDocumentCollection(
                id: "actors",
                name: "actors",
                label: "Actors",
                sourcePath: "data/actors",
                declaredDocumentType: .actor,
                documents: [],
                folders: folders
            )],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 1,
                topLevelDocumentCount: 0,
                embeddedDocumentCount: 0,
                folderCount: folders.count,
                unknownFieldCount: 0,
                documentCounts: [:]
            )
        )
        return try await FoundryVTTDomainMapper().map(
            package: package,
            sourceUrl: URL(filePath: "/tmp/foundry-folder-cycle-test.json"),
            sourceScopeId: try #require(UUID(uuidString: "5C0B1A57-3F3E-4D0B-9B52-0E3B8F6F2A12")),
            selectedCategories: [.actors],
            resourceLoader: { _ in Data() }
        )
    }
}
