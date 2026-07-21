// @copyright André Trettin

import CoreRPG
import Foundation
import Testing

@Suite("Foundry RuleRPG source archive")
struct FoundryImportArchiveTests {
    @Test func roundTripsArchiveAndListsSummary() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FoundryImportArchiveTests-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = FoundryVTTImportPackage(
            sourceSHA256: String(repeating: "a", count: 64),
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: [],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 0,
                topLevelDocumentCount: 0,
                embeddedDocumentCount: 0,
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [:]
            )
        )
        let archive = FoundryImportArchive(
            id: FoundryRuleIdentity.uuid(for: "archive-test"),
            sourceFormat: "foundry-world",
            sourceSemanticKey: "world:demo",
            importedAt: Date(timeIntervalSince1970: 1_234),
            sourceFileName: "world.zip",
            package: package,
            mappings: [FoundryImportMapping(
                foundryIdentifier: "Actor.hero",
                references: [FoundryImportMappingReference(
                    module: .value,
                    itemID: FoundryRuleIdentity.uuid(for: "hero")
                )]
            )]
        )
        let store = FoundryImportArchiveStore(directoryURL: directory)

        try await store.save(archive)

        #expect(try await store.archive(id: archive.id) == archive)
        let summaries = try await store.summaries()
        #expect(summaries.count == 1)
        #expect(summaries.first?.id == archive.id)
        #expect(summaries.first?.sourceFileName == "world.zip")
        let sources = try await store.sourceRegistryEntries()
        #expect(sources.first?.scopeID == archive.id)
        #expect(sources.first?.format == "foundry-world")
        #expect(sources.first?.semanticKey == "world:demo")
    }

    @Test func rejectsAnOversizedEncodedArchive() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FoundryImportArchiveLimitTests-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let package = FoundryVTTImportPackage(
            kind: .exportedDocument,
            manifestPath: nil,
            manifest: nil,
            collections: [],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 0,
                topLevelDocumentCount: 0,
                embeddedDocumentCount: 0,
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [:]
            )
        )
        let archive = FoundryImportArchive(
            id: UUID(),
            sourceFileName: "large.json",
            package: package,
            mappings: [],
            warnings: [String(repeating: "x", count: 512)]
        )
        let store = FoundryImportArchiveStore(
            directoryURL: directory,
            maximumEncodedByteCount: 64
        )

        await #expect(throws: FoundryImportArchiveStoreError.self) {
            try await store.save(archive)
        }
    }

    @Test("Synced archives preserve an explicitly reassigned bridge identity")
    func archiveSourceHintPreservesBridgeIntrinsicAlias() async throws {
        // Given
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FoundryImportArchiveBridgeIdentityTests-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let intrinsicScopeID = UUID()
        let reassignedScopeID = UUID()
        let package = FoundryVTTImportPackage(
            kind: .world,
            manifestPath: "world.json",
            manifest: FoundryVTTPackageManifest(
                kind: .world,
                id: "demo",
                title: "Demo",
                descriptionHTML: nil,
                version: "1",
                systemID: "demo",
                compatibility: FoundryCompatibility(minimum: nil, verified: nil, maximum: nil),
                rawData: .object([
                    "source": .object([
                        "instanceID": .string(intrinsicScopeID.uuidString),
                    ]),
                ])
            ),
            collections: [],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 0,
                topLevelDocumentCount: 0,
                embeddedDocumentCount: 0,
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [:]
            )
        )
        let archive = FoundryImportArchive(
            id: reassignedScopeID,
            sourceScopeID: reassignedScopeID,
            sourceFormat: "foundry-world",
            sourceSemanticKey: "world:demo",
            sourceFileName: "demo.mrpgfoundry",
            package: package,
            mappings: []
        )
        let store = FoundryImportArchiveStore(directoryURL: directory)
        try await store.save(archive)

        // When
        let sources = try await store.sourceRegistryEntries()

        // Then
        #expect(sources.first?.scopeID == reassignedScopeID)
        #expect(sources.first?.intrinsicScopeAlias == intrinsicScopeID)
    }

    @Test("Corrupt archives do not hide valid hints and duplicate scopes use the newest archive")
    func sourceHintsRecoverIndependently() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "FoundryImportArchiveRecoveryTests-\(UUID().uuidString)"
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let scopeID = UUID()
        let package = FoundryVTTImportPackage(
            sourceSHA256: "source-hash",
            kind: .world,
            manifestPath: nil,
            manifest: nil,
            collections: [],
            resources: [],
            diagnostics: [],
            statistics: FoundryVTTImportStatistics(
                collectionCount: 0,
                topLevelDocumentCount: 0,
                embeddedDocumentCount: 0,
                folderCount: 0,
                unknownFieldCount: 0,
                documentCounts: [:]
            )
        )
        let store = FoundryImportArchiveStore(directoryURL: directory)
        try await store.save(FoundryImportArchive(
            id: UUID(),
            sourceScopeID: scopeID,
            sourceFormat: "foundry-world",
            sourceSemanticKey: "world:demo",
            importedAt: Date(timeIntervalSince1970: 1),
            sourceFileName: "old-world.zip",
            package: package,
            mappings: []
        ))
        try await store.save(FoundryImportArchive(
            id: UUID(),
            sourceScopeID: scopeID,
            sourceFormat: "foundry-world",
            sourceSemanticKey: "world:demo",
            importedAt: Date(timeIntervalSince1970: 2),
            sourceFileName: "new-world.zip",
            package: package,
            mappings: []
        ))
        try Data("not-json".utf8).write(
            to: directory.appending(path: "corrupt.json"),
            options: .atomic
        )

        let sources = try await store.sourceRegistryEntries()
        let summaries = try await store.summaries()

        #expect(sources.count == 1)
        #expect(sources.first?.scopeID == scopeID)
        #expect(sources.first?.lastKnownPathAlias == "new-world.zip")
        #expect(sources.first?.lastImportedAt == Date(timeIntervalSince1970: 2))
        #expect(summaries.count == 2)
    }
}
