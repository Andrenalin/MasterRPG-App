// @copyright André Trettin

import Foundation
import Testing

@testable import CoreRPG

@Suite("External import source identity")
struct ExternalImportSourceRegistryTests {
    // CODE_AUDIT_21 §4.2: the alias is stored and compared, so it keeps the form `URL.path` had.
    @Test("The path alias of a folder source has no trailing slash")
    func folderPathAliasHasNoTrailingSlash() throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let world = directory.appending(path: "My World", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: world, withIntermediateDirectories: true)
        let file = world.appending(path: "world.json")
        try Data("one".utf8).write(to: file)

        let folderAlias = ExternalImportSourceRegistry.aliases(for: world).path
        let fileAlias = ExternalImportSourceRegistry.aliases(for: file).path

        #expect(folderAlias.hasSuffix("/My World"))
        #expect(folderAlias == ExternalImportSourceRegistry.aliases(for: directory.appending(path: "My World")).path)
        #expect(fileAlias == folderAlias + "/world.json")
        #expect(ExternalImportSourceRegistry.pathAlias(of: URL(filePath: "/")) == "/")
    }

    @Test("Follows a renamed source by file identity")
    func followsRename() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "world.json")
        try Data("one".utf8).write(to: source)
        let registry = ExternalImportSourceRegistry(directoryUrl: directory.appending(path: "registry"))
        let descriptor = ExternalImportSourceDescriptor(
            format: "foundry-world",
            semanticKey: "world:demo",
            sourceUrl: source,
            contentHash: "one"
        )
        let firstScope = try #require(try await registry.resolve(descriptor).scopeId)
        try await registry.register(scopeId: firstScope, descriptor: descriptor)

        let renamed = directory.appending(path: "renamed.json")
        try FileManager.default.moveItem(at: source, to: renamed)
        let renamedDescriptor = ExternalImportSourceDescriptor(
            format: "foundry-world",
            semanticKey: "world:demo",
            sourceUrl: renamed,
            contentHash: "one"
        )

        #expect(try await registry.resolve(renamedDescriptor).scopeId == firstScope)
    }

    @Test("Copied worlds require an explicit identity choice")
    func copiedWorldRequiresChoice() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "first.json")
        let copy = directory.appending(path: "copy.json")
        try Data("same".utf8).write(to: first)
        try FileManager.default.copyItem(at: first, to: copy)
        let registry = ExternalImportSourceRegistry(directoryUrl: directory.appending(path: "registry"))
        let firstDescriptor = ExternalImportSourceDescriptor(
            format: "foundry-world",
            semanticKey: "world:demo",
            sourceUrl: first
        )
        let firstScope = try #require(try await registry.resolve(firstDescriptor).scopeId)
        try await registry.register(scopeId: firstScope, descriptor: firstDescriptor)

        let resolution = try await registry.resolve(ExternalImportSourceDescriptor(
            format: "foundry-world",
            semanticKey: "world:demo",
            sourceUrl: copy
        ))
        guard case .requiresSelection(let existing, let proposedScopeId) = resolution else {
            Issue.record("Expected copied world identity choice")
            return
        }
        #expect(existing.map(\.scopeId) == [firstScope])
        #expect(proposedScopeId != firstScope)
    }

    @Test("System semantic identity can update across package locations")
    func systemSemanticIdentityIsReusable() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "ds4-v1.zip")
        let second = directory.appending(path: "ds4-v2.zip")
        try Data("one".utf8).write(to: first)
        try Data("two".utf8).write(to: second)
        let registry = ExternalImportSourceRegistry(directoryUrl: directory.appending(path: "registry"))
        let firstDescriptor = ExternalImportSourceDescriptor(
            format: "foundry-system",
            semanticKey: "system:ds4",
            sourceUrl: first,
            semanticMatchPolicy: .automatic
        )
        let firstScope = try #require(try await registry.resolve(firstDescriptor).scopeId)
        try await registry.register(scopeId: firstScope, descriptor: firstDescriptor)
        let secondDescriptor = ExternalImportSourceDescriptor(
            format: "foundry-system",
            semanticKey: "system:ds4",
            sourceUrl: second,
            semanticMatchPolicy: .automatic
        )

        #expect(try await registry.resolve(secondDescriptor).scopeId == firstScope)
    }

    @Test("An intrinsic bridge scope wins over aliases")
    func intrinsicScopeWins() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "bridge.mrpgfoundry")
        try Data().write(to: source)
        let registry = ExternalImportSourceRegistry(directoryUrl: directory.appending(path: "registry"))
        let intrinsic = UUID()

        #expect(try await registry.resolve(ExternalImportSourceDescriptor(
            format: "foundry-bridge",
            intrinsicScopeId: intrinsic,
            sourceUrl: source
        )).scopeId == intrinsic)
    }

    @Test("Replacing an arbitrary source at the same path requires confirmation")
    func pathReplacementRequiresChoice() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "map.uvtt")
        try Data("first".utf8).write(to: source)
        let registry = ExternalImportSourceRegistry(directoryUrl: directory.appending(path: "registry"))
        let first = ExternalImportSourceDescriptor(
            format: "universal-vtt",
            sourceUrl: source,
            contentHash: "first"
        )
        let firstScope = try #require(try await registry.resolve(first).scopeId)
        try await registry.register(scopeId: firstScope, descriptor: first)

        try FileManager.default.removeItem(at: source)
        try Data("unrelated".utf8).write(to: source)
        let resolution = try await registry.resolve(ExternalImportSourceDescriptor(
            format: "universal-vtt",
            sourceUrl: source,
            contentHash: "unrelated"
        ))

        guard case .requiresSelection(let existing, let proposed) = resolution else {
            Issue.record("Expected an explicit source identity choice")
            return
        }
        #expect(existing.map(\.scopeId) == [firstScope])
        #expect(proposed != firstScope)
    }

    @Test("Separate registry actors merge concurrent updates")
    func concurrentRegistriesDoNotLoseUpdates() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let indexDirectory = directory.appending(path: "registry")
        let firstURL = directory.appending(path: "first.uvtt")
        let secondURL = directory.appending(path: "second.uvtt")
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        let firstRegistry = ExternalImportSourceRegistry(directoryUrl: indexDirectory)
        let secondRegistry = ExternalImportSourceRegistry(directoryUrl: indexDirectory)
        let firstScope = UUID()
        let secondScope = UUID()
        let first = ExternalImportSourceDescriptor(format: "universal-vtt", sourceUrl: firstURL)
        let second = ExternalImportSourceDescriptor(format: "universal-vtt", sourceUrl: secondURL)

        async let firstRegistration: Void = firstRegistry.register(scopeId: firstScope, descriptor: first)
        async let secondRegistration: Void = secondRegistry.register(scopeId: secondScope, descriptor: second)
        _ = try await (firstRegistration, secondRegistration)

        let entries = try await firstRegistry.allEntries()
        #expect(Set(entries.map(\.scopeId)) == Set([firstScope, secondScope]))
    }

    @Test("First allocation converges before separate registries synchronize")
    func firstAllocationConvergesAcrossRegistries() async throws {
        // Given
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "shared.uvtt")
        try Data("same source".utf8).write(to: source)
        let indexDirectory = directory.appending(path: "registry")
        let firstRegistry = ExternalImportSourceRegistry(directoryUrl: indexDirectory)
        let secondRegistry = ExternalImportSourceRegistry(directoryUrl: indexDirectory)
        let descriptor = ExternalImportSourceDescriptor(
            format: "universal-vtt",
            sourceUrl: source,
            contentHash: "same-hash"
        )
        let firstReviewScope = try #require(try await firstRegistry.resolve(descriptor).scopeId)
        let secondReviewScope = try #require(try await secondRegistry.resolve(descriptor).scopeId)
        #expect(firstReviewScope == secondReviewScope)

        // When
        let firstClaim = try await firstRegistry.claim(
            .resolved(scopeId: firstReviewScope),
            descriptor: descriptor
        )
        let secondClaim = try await secondRegistry.claim(
            .resolved(scopeId: secondReviewScope),
            descriptor: descriptor
        )

        // Then
        #expect(firstClaim == .claimed(scopeId: firstReviewScope))
        #expect(secondClaim == .claimed(scopeId: firstReviewScope))
        let entries = try await firstRegistry.allEntries()
        #expect(entries.map(\.scopeId) == [firstReviewScope])
    }

    @Test("Content fingerprints converge across different device paths")
    func contentFingerprintConvergesAcrossPaths() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appending(path: "device-a/map.uvtt")
        let secondURL = directory.appending(path: "device-b/copied-map.uvtt")
        try FileManager.default.createDirectory(
            at: firstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("map".utf8).write(to: firstURL)
        try Data("map".utf8).write(to: secondURL)
        let firstRegistry = ExternalImportSourceRegistry(
            directoryUrl: directory.appending(path: "device-a-registry")
        )
        let secondRegistry = ExternalImportSourceRegistry(
            directoryUrl: directory.appending(path: "device-b-registry")
        )

        let first = try #require(try await firstRegistry.resolve(ExternalImportSourceDescriptor(
            format: "universal-vtt",
            sourceUrl: firstURL,
            contentHash: "shared-fingerprint"
        )).scopeId)
        let second = try #require(try await secondRegistry.resolve(ExternalImportSourceDescriptor(
            format: "universal-vtt",
            sourceUrl: secondURL,
            contentHash: "shared-fingerprint"
        )).scopeId)

        #expect(first == second)
    }

    @Test("Semantic package identity converges across versions before synchronization")
    func semanticIdentityPrecedesChangingContentFingerprint() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appending(path: "ds4-v1.zip")
        let secondURL = directory.appending(path: "ds4-v2.zip")
        try Data("v1".utf8).write(to: firstURL)
        try Data("v2".utf8).write(to: secondURL)
        let firstRegistry = ExternalImportSourceRegistry(
            directoryUrl: directory.appending(path: "device-a-registry")
        )
        let secondRegistry = ExternalImportSourceRegistry(
            directoryUrl: directory.appending(path: "device-b-registry")
        )

        let first = try #require(try await firstRegistry.resolve(ExternalImportSourceDescriptor(
            format: "foundry-system",
            semanticKey: "system:ds4",
            sourceUrl: firstURL,
            contentHash: "v1-hash",
            semanticMatchPolicy: .automatic
        )).scopeId)
        let second = try #require(try await secondRegistry.resolve(ExternalImportSourceDescriptor(
            format: "foundry-system",
            semanticKey: "system:ds4",
            sourceUrl: secondURL,
            contentHash: "v2-hash",
            semanticMatchPolicy: .automatic
        )).scopeId)

        #expect(first == second)
    }

    @Test("A concurrent semantic collision still offers a distinct copied-source scope")
    func concurrentSemanticCollisionRequiresCopyChoice() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let firstURL = directory.appending(path: "first/world.json")
        let secondURL = directory.appending(path: "second/world.json")
        try FileManager.default.createDirectory(
            at: firstURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: secondURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("first".utf8).write(to: firstURL)
        try Data("second".utf8).write(to: secondURL)
        let registry = ExternalImportSourceRegistry(directoryUrl: directory.appending(path: "registry"))
        let firstDescriptor = ExternalImportSourceDescriptor(
            format: "foundry-world",
            semanticKey: "world:demo",
            sourceUrl: firstURL,
            contentHash: "first"
        )
        let secondDescriptor = ExternalImportSourceDescriptor(
            format: "foundry-world",
            semanticKey: "world:demo",
            sourceUrl: secondURL,
            contentHash: "second"
        )
        let firstScope = try #require(try await registry.resolve(firstDescriptor).scopeId)
        let secondStaleScope = try #require(try await registry.resolve(secondDescriptor).scopeId)
        #expect(firstScope == secondStaleScope)
        _ = try await registry.claim(.resolved(scopeId: firstScope), descriptor: firstDescriptor)

        let secondClaim = try await registry.claim(
            .resolved(scopeId: secondStaleScope),
            descriptor: secondDescriptor
        )

        guard case .requiresSelection(let existing, let proposedScopeId) = secondClaim else {
            Issue.record("Expected a copied-source identity choice")
            return
        }
        #expect(existing.map(\.scopeId) == [firstScope])
        #expect(proposedScopeId != firstScope)
    }

    @Test("Duplicate fallback scopes retain the newest identity hint")
    func duplicateFallbackScopesUseNewestEntry() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "copy.json")
        try Data().write(to: source)
        let scopeId = UUID()
        let old = ExternalImportSourceEntry(
            scopeId: scopeId,
            format: "foundry-world",
            semanticKey: "world:demo",
            fileResourceAlias: nil,
            volumeResourceAlias: nil,
            lastKnownPathAlias: "old.json",
            lastContentHash: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            lastImportedAt: Date(timeIntervalSince1970: 1)
        )
        let newest = ExternalImportSourceEntry(
            scopeId: scopeId,
            format: "foundry-world",
            semanticKey: "world:demo",
            fileResourceAlias: nil,
            volumeResourceAlias: nil,
            lastKnownPathAlias: "newest.json",
            lastContentHash: nil,
            createdAt: Date(timeIntervalSince1970: 1),
            lastImportedAt: Date(timeIntervalSince1970: 2)
        )
        let registry = ExternalImportSourceRegistry(directoryUrl: directory.appending(path: "registry"))

        let resolution = try await registry.resolve(
            ExternalImportSourceDescriptor(
                format: "foundry-world",
                semanticKey: "world:demo",
                sourceUrl: source
            ),
            fallbackEntries: [old, newest]
        )

        guard case .requiresSelection(let existing, _) = resolution else {
            Issue.record("Expected a copied-world identity choice")
            return
        }
        #expect(existing.count == 1)
        #expect(existing.first?.scopeId == scopeId)
        #expect(existing.first?.lastKnownPathAlias == "newest.json")
    }

    @Test("Choosing a new bridge source durably records both intrinsic identity candidates")
    func bridgeIntrinsicIdentityFollowsExplicitReassignment() async throws {
        // Given
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = directory.appending(path: "original.mrpgfoundry")
        let duplicate = directory.appending(path: "duplicate.mrpgfoundry")
        let unknownExport = directory.appending(path: "unknown.mrpgfoundry")
        try Data("original".utf8).write(to: original)
        try Data("duplicate".utf8).write(to: duplicate)
        try Data("unknown".utf8).write(to: unknownExport)
        let registry = ExternalImportSourceRegistry(directoryUrl: directory.appending(path: "registry"))
        let intrinsicScopeId = UUID()
        let originalDescriptor = ExternalImportSourceDescriptor(
            format: "foundry-world",
            semanticKey: "world:demo",
            intrinsicScopeId: intrinsicScopeId,
            sourceUrl: original
        )
        try await registry.register(scopeId: intrinsicScopeId, descriptor: originalDescriptor)
        let duplicateDescriptor = ExternalImportSourceDescriptor(
            format: "foundry-world",
            semanticKey: "world:demo",
            intrinsicScopeId: intrinsicScopeId,
            sourceUrl: duplicate
        )
        let duplicateResolution = try await registry.resolve(duplicateDescriptor)
        guard case .requiresSelection(_, let proposedScopeId) = duplicateResolution else {
            Issue.record("Expected the duplicated bridge identity to require a choice")
            return
        }

        // When
        let claim = try await registry.claim(
            .selectedNew(scopeId: proposedScopeId),
            descriptor: duplicateDescriptor
        )

        // Then
        #expect(claim == .claimed(scopeId: proposedScopeId))
        let entries = try await registry.allEntries()
        #expect(entries.first { $0.scopeId == intrinsicScopeId }?.intrinsicScopeAlias == nil)
        #expect(entries.first { $0.scopeId == proposedScopeId }?.intrinsicScopeAlias == intrinsicScopeId)
        #expect(try await registry.resolve(originalDescriptor).scopeId == intrinsicScopeId)
        #expect(try await registry.resolve(duplicateDescriptor).scopeId == proposedScopeId)

        let unknownResolution = try await registry.resolve(ExternalImportSourceDescriptor(
            format: "foundry-world",
            semanticKey: "world:demo",
            intrinsicScopeId: intrinsicScopeId,
            sourceUrl: unknownExport
        ))
        guard case .requiresSelection(let candidates, _) = unknownResolution else {
            Issue.record("Expected an unknown path with a duplicated intrinsic ID to require a choice")
            return
        }
        #expect(Set(candidates.map(\.scopeId)) == Set([intrinsicScopeId, proposedScopeId]))
    }

    @Test("Version one source indexes decode without the optional intrinsic alias")
    func versionOneIndexRemainsReadable() async throws {
        // Given
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let indexDirectory = directory.appending(path: "registry", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: indexDirectory, withIntermediateDirectories: true)
        let scopeId = UUID()
        let timestamp = Date(timeIntervalSince1970: 123)
        let legacyEntry = LegacySourceEntry(
            scopeId: scopeId,
            format: "foundry-world",
            semanticKey: "world:legacy",
            fileResourceAlias: nil,
            volumeResourceAlias: nil,
            lastKnownPathAlias: "legacy.mrpgfoundry",
            lastContentHash: nil,
            createdAt: timestamp,
            lastImportedAt: timestamp
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(LegacySourceIndex(formatVersion: 1, entries: [legacyEntry]))
            .write(to: indexDirectory.appending(path: "sources.json"), options: .atomic)
        let registry = ExternalImportSourceRegistry(directoryUrl: indexDirectory)

        // When
        let entries = try await registry.allEntries()

        // Then
        #expect(entries.count == 1)
        #expect(entries.first?.scopeId == scopeId)
        #expect(entries.first?.intrinsicScopeAlias == nil)
    }

    @Test("Synced archive hints restore semantic source identity")
    func fallbackEntriesRestoreIdentity() async throws {
        let directory = try temporaryRegistryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appending(path: "ds4.zip")
        try Data().write(to: source)
        let expectedScope = UUID()
        let importedAt = Date(timeIntervalSince1970: 10)
        let fallback = ExternalImportSourceEntry(
            scopeId: expectedScope,
            format: "foundry-system",
            semanticKey: "system:ds4",
            fileResourceAlias: nil,
            volumeResourceAlias: nil,
            lastKnownPathAlias: "old-device.zip",
            lastContentHash: "old",
            createdAt: importedAt,
            lastImportedAt: importedAt
        )
        let registry = ExternalImportSourceRegistry(directoryUrl: directory.appending(path: "empty-registry"))

        let resolution = try await registry.resolve(
            ExternalImportSourceDescriptor(
                format: "foundry-system",
                semanticKey: "system:ds4",
                sourceUrl: source,
                semanticMatchPolicy: .automatic
            ),
            fallbackEntries: [fallback]
        )

        #expect(resolution.scopeId == expectedScope)
    }
}

private struct LegacySourceIndex: Encodable {
    let formatVersion: Int
    let entries: [LegacySourceEntry]
}

private struct LegacySourceEntry: Encodable {
    let scopeId: UUID
    let format: String
    let semanticKey: String?
    let fileResourceAlias: String?
    let volumeResourceAlias: String?
    let lastKnownPathAlias: String
    let lastContentHash: String?
    let createdAt: Date
    let lastImportedAt: Date

    /// A real version-one index stores `scopeID`; the property follows the `Id` casing.
    /// See CODE_AUDIT_29 §4.3.
    private enum CodingKeys: String, CodingKey {
        case scopeId = "scopeID"
        case format, semanticKey, fileResourceAlias, volumeResourceAlias, lastKnownPathAlias, lastContentHash, createdAt, lastImportedAt
    }
}

private extension ExternalImportSourceResolution {
    var scopeId: UUID? {
        guard case .resolved(let scopeId) = self else { return nil }
        return scopeId
    }
}

private func temporaryRegistryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory.appending(
        path: "ExternalImportSourceRegistryTests-\(UUID().uuidString)",
        directoryHint: .isDirectory
    )
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}
