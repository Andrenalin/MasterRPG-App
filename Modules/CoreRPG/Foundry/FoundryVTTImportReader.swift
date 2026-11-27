// @copyright André Trettin

import CryptoKit
import Foundation

// MARK: - Public API

/// Reads Foundry VTT system, module, world, compendium, and exported-document artifacts.
///
/// This is a data transport only: JavaScript is never evaluated and HTML is retained as text.
public struct FoundryVTTImportReader: Sendable {
    public let limits: FoundryImportLimits
    private let bridgeResourceCache: FoundryBridgeResourceCache
    private let zipDataSourceCache: FoundryZIPDataSourceCache

    public init(limits: FoundryImportLimits = .default) {
        self.limits = limits
        bridgeResourceCache = FoundryBridgeResourceCache(limits: limits)
        zipDataSourceCache = FoundryZIPDataSourceCache(limits: limits)
    }

    /// Drops the decoded assets and parsed archives kept for resource reads. Call it when the
    /// import has been committed: the bridge cache holds every asset of the source (up to the
    /// resource batch limit) until the next preflight otherwise. See CODE_AUDIT_26 §7.3.
    public func releaseCachedSources() async {
        await bridgeResourceCache.invalidate(sourceUrl: URL(filePath: "/"))
        await zipDataSourceCache.invalidate(sourceUrl: URL(filePath: "/"))
    }

    public func read(from url: URL) async throws -> FoundryVTTImportPackage {
        if url.lastPathComponent.lowercased().hasSuffix(".mrpgfoundry") {
            await bridgeResourceCache.invalidate(sourceUrl: url)
        }
        await zipDataSourceCache.invalidate(sourceUrl: url)
        let limits = limits
        // Structured and scope-balanced; cancellation propagates. See CODE_AUDIT_18 §4.4.
        let (decodedPackage, decodedSource) = try await url.withSecurityScopedAccess { url in
            // Parse the source once and hand it to the decoder, instead of letting
            // `decode(from:)` reparse it internally — the parsed source is reused below to
            // avoid a second full read+parse of the same (up to 1 GiB) archive. See CODE_AUDIT_9 §7.3.
            let source = try FoundryVTTDataSource(url: url, limits: limits)
            let package = try FoundryVTTDecoder(limits: limits).decode(source: source)
            return (package: package, source: source)
        }
        var package = decodedPackage
        // The first resource read reuses the source parsed and hashed here instead of reading and
        // hashing the (up to 1 GiB) archive again. See CODE_AUDIT_29 §7.6.
        await zipDataSourceCache.seed(decodedSource, for: url)

        if package.kind == .system {
            do {
                let rulePackage: FoundryRulePackage
                if case .archive(let archive, let sourceSHA256) = decodedSource {
                    // Reuse the ZIP central directory already parsed above rather than
                    // re-reading and re-parsing the same archive from disk a second time.
                    rulePackage = try await FoundrySystemPackageReader(limits: limits).read(
                        reusingArchive: archive,
                        sourceSHA256: sourceSHA256
                    )
                } else {
                    rulePackage = try await FoundrySystemPackageReader(limits: limits).read(from: url)
                }
                package = package.with(rulePackage: rulePackage)
            } catch is CancellationError {
                throw CancellationError()
            } catch {
                package = package.with(diagnostic: FoundryImportDiagnostic(
                    severity: .information,
                    code: "rule-package-not-derived",
                    message: "The complete Foundry documents were decoded, but the RuleRPG compatibility view could not be derived: \(error.localizedDescription)"
                ))
            }
        }
        return package
    }

    /// Reopens packaged resources using the source identity and integrity metadata produced by
    /// `read(from:)`. Remote and installation-relative resources are deliberately not fetched.
    public func readResources(
        _ resources: [FoundryPackageResource],
        from url: URL,
        in package: FoundryVTTImportPackage
    ) async throws -> [FoundryPackageResourceData] {
        guard Set(resources).count == resources.count else {
            throw FoundryImportError.duplicateResourceRequest
        }
        let limits = limits
        let bridgeResourceCache = bridgeResourceCache
        let zipDataSourceCache = zipDataSourceCache
        // Structured and scope-balanced; cancellation propagates. See CODE_AUDIT_18 §4.4.
        return try await url.withSecurityScopedAccess { url in
            let source = try await zipDataSourceCache.dataSource(for: url)
            if let expectedSHA256 = package.sourceSHA256,
               source.sourceSHA256 != expectedSHA256 {
                throw FoundryImportError.sourceMismatch
            }
            if let manifestPath = package.manifestPath,
               let expectedManifest = package.manifest?.rawData {
                guard let data = try source.data(forPath: manifestPath),
                      try FoundryJSONDecoding.decode(data, context: manifestPath) == expectedManifest else {
                    throw FoundryImportError.sourceMismatch
                }
            }

            let issued = Set(package.resources)
            for resource in resources {
                guard issued.contains(resource), resource.location == .packaged,
                      resource.packagePath != nil,
                      resource.byteCount != nil,
                      resource.sha256 != nil else {
                    throw FoundryImportError.resourceUnavailable(resource.logicalPath)
                }
            }

            let isBridge = url.lastPathComponent.lowercased().hasSuffix(".mrpgfoundry")
            let bridgeAssets: [String: Data]?
            if isBridge {
                bridgeAssets = try await bridgeResourceCache.resourceData(
                    logicalPaths: Set(resources.map(\.logicalPath)),
                    sourceUrl: url
                )
            } else {
                bridgeAssets = nil
            }

            var byteCount = 0
            var result: [FoundryPackageResourceData] = []
            result.reserveCapacity(resources.count)
            for resource in resources {
                try Task.checkCancellation()
                guard issued.contains(resource), resource.location == .packaged,
                      let path = resource.packagePath,
                      let expectedSize = resource.byteCount,
                      let expectedSHA256 = resource.sha256 else {
                    throw FoundryImportError.resourceUnavailable(resource.logicalPath)
                }
                let data: Data
                if let bridgeAssets {
                    guard let bridgeData = bridgeAssets[resource.logicalPath] else {
                        throw FoundryImportError.resourceUnavailable(resource.logicalPath)
                    }
                    data = bridgeData
                } else {
                    guard let reopened = try source.data(forPath: path) else {
                        throw FoundryImportError.resourceUnavailable(resource.logicalPath)
                    }
                    data = reopened
                }
                guard data.count == expectedSize, foundrySHA256(data) == expectedSHA256 else {
                    throw FoundryImportError.resourceIntegrityFailure(resource.logicalPath)
                }
                let (nextCount, overflow) = byteCount.addingReportingOverflow(data.count)
                guard !overflow, nextCount <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextCount)
                }
                byteCount = nextCount
                result.append(FoundryPackageResourceData(resource: resource, data: data))
            }
            return result
        }
    }

    public func readResource(
        _ resource: FoundryPackageResource,
        from url: URL,
        in package: FoundryVTTImportPackage
    ) async throws -> Data {
        guard let data = try await readResources([resource], from: url, in: package).first?.data else {
            throw FoundryImportError.resourceUnavailable(resource.logicalPath)
        }
        return data
    }

    /// Reopens one descriptor without retaining the full preflight package. Integrity is still
    /// checked against the descriptor; callers that retain a package should prefer
    /// `readResources(_:from:in:)` for source-manifest validation and batch limits.
    public func resourceData(
        for resource: FoundryPackageResource,
        from sourceUrl: URL
    ) async throws -> FoundryPackageResourceData {
        let limits = limits
        let bridgeResourceCache = bridgeResourceCache
        let zipDataSourceCache = zipDataSourceCache
        // Structured and scope-balanced; cancellation propagates. See CODE_AUDIT_18 §4.4.
        return try await sourceUrl.withSecurityScopedAccess { sourceUrl in
            guard resource.location == .packaged,
                  let expectedSize = resource.byteCount,
                  let expectedSHA256 = resource.sha256 else {
                throw FoundryImportError.resourceUnavailable(resource.logicalPath)
            }
            let data: Data
            let lowercasedName = sourceUrl.lastPathComponent.lowercased()
            if lowercasedName.hasSuffix(".mrpgfoundry") {
                let bridgeResources = try await bridgeResourceCache.resourceData(
                    logicalPaths: [resource.logicalPath],
                    sourceUrl: sourceUrl
                )
                guard let bridgeData = bridgeResources[resource.logicalPath] else {
                    throw FoundryImportError.resourceUnavailable(resource.logicalPath)
                }
                data = bridgeData
            } else if resource.packagePath == "universal-vtt/image"
                        || lowercasedName.hasSuffix(".uvtt")
                        || lowercasedName.hasSuffix(".dd2vtt") {
                data = try UniversalVTTReader.imageDataSynchronously(from: sourceUrl, limits: limits)
            } else {
                let source = try await zipDataSourceCache.dataSource(for: sourceUrl)
                guard let path = resource.packagePath,
                      let reopened = try source.data(forPath: path) else {
                    throw FoundryImportError.resourceUnavailable(resource.logicalPath)
                }
                data = reopened
            }
            guard data.count == expectedSize, foundrySHA256(data) == expectedSHA256 else {
                throw FoundryImportError.resourceIntegrityFailure(resource.logicalPath)
            }
            return FoundryPackageResourceData(resource: resource, data: data)
        }
    }
}

// MARK: - Package Mutation Helpers

private extension FoundryVTTImportPackage {
    func with(rulePackage: FoundryRulePackage) -> Self {
        Self(
            formatVersion: formatVersion,
            sourceSHA256: sourceSHA256,
            kind: kind,
            manifestPath: manifestPath,
            manifest: manifest,
            collections: collections,
            resources: resources,
            textResources: textResources,
            diagnostics: diagnostics,
            statistics: statistics,
            rulePackage: rulePackage
        )
    }

    func with(diagnostic: FoundryImportDiagnostic) -> Self {
        Self(
            formatVersion: formatVersion,
            sourceSHA256: sourceSHA256,
            kind: kind,
            manifestPath: manifestPath,
            manifest: manifest,
            collections: collections,
            resources: resources,
            textResources: textResources,
            diagnostics: diagnostics + [diagnostic],
            statistics: statistics,
            rulePackage: rulePackage
        )
    }
}

// MARK: - Package Decode Orchestration

// MARK: - Manifest Selection & Decoding

// MARK: - Collection Discovery

// `FoundryLevelDBLiveFiles`, the LevelDB-specific `FoundryVTTDecoder` extension
// (decodeLevelDBCollection/decodeLegacyDatabase/decodeJSONCollection), and
// `FoundryLevelDBRecordMerger` now live in `FoundryVTTDecoder+CollectionDecoding.swift`.
// See CODE_AUDIT §9.8.

// MARK: - Document Tree Assembly

// MARK: - LevelDB Key Parsing

// MARK: - Document Type Inference

// MARK: - Embedded Document Extraction

// MARK: - Known Field Tracking

// MARK: - Description Extraction

// MARK: - Document Sorting

// MARK: - JSON Value & Data Helpers
//
// `FoundryPackagePath` (path utilities) and `FoundryJSONDecoding` (JSON decoding) now live in
// the shared `FoundryPackageResolution.swift`, used by both this reader and
// `FoundrySystemPackageReader`. See CODE_AUDIT §9.2, §9.3.

// MARK: - Document Identity Validation

// MARK: - Import Statistics

// `FoundryAssetPathCollector` (asset path collection) and `FoundryPackageResourceResolver`
// (resource resolution) now live in the shared `FoundryPackageResolution.swift`, used by both
// this reader and `FoundrySystemPackageReader`. See CODE_AUDIT §9.1, §9.4.

/// A reader-scoped cache of the parsed `FoundryVTTDataSource` for a standard ZIP-backed source
/// (system/module/world archives) — the ZIP-format counterpart to `FoundryBridgeResourceCache`
/// below. Without this, `readResources(_:from:in:)`/`resourceData(for:from:)` each independently
/// re-read the whole archive off disk, re-parsed its ZIP central directory, and re-hashed every
/// byte just to extract one file — for a world/module with N packaged assets (images, audio),
/// mapper attachment closures requesting resources one at a time turned into N full re-parses of
/// an archive that can be up to 1GiB, instead of one. See CODE_AUDIT §7.1.
// MARK: - Source & Resource Caching

private actor FoundryZIPDataSourceCache {
    let limits: FoundryImportLimits
    private var sourcePath: String?
    private var dataSource: FoundryVTTDataSource?

    init(limits: FoundryImportLimits) {
        self.limits = limits
    }

    func invalidate(sourceUrl _: URL) {
        sourcePath = nil
        dataSource = nil
    }

    func seed(_ source: FoundryVTTDataSource, for sourceUrl: URL) {
        sourcePath = sourceUrl.standardizedFileURL.path(percentEncoded: false)
        dataSource = source
    }

    func dataSource(for sourceUrl: URL) throws -> FoundryVTTDataSource {
        try Task.checkCancellation()
        let path = sourceUrl.standardizedFileURL.path(percentEncoded: false)
        if sourcePath == path, let dataSource {
            return dataSource
        }
        let created = try FoundryVTTDataSource(url: sourceUrl, limits: limits)
        sourcePath = path
        dataSource = created
        return created
    }
}

/// A reader-scoped, bounded snapshot of one bridge export. Mapper attachment closures request
/// resources one at a time, so retaining the already-validated bridge assets here prevents an
/// O(resource count × export size) sequence of file rereads. A new preflight invalidates the
/// matching source, while one commit observes a coherent source snapshot.
private actor FoundryBridgeResourceCache {
    let limits: FoundryImportLimits
    private var sourcePath: String?
    private var resources: [String: Data] = [:]

    init(limits: FoundryImportLimits) {
        self.limits = limits
    }

    func invalidate(sourceUrl _: URL) {
        sourcePath = nil
        resources = [:]
    }

    func resourceData(
        logicalPaths: Set<String>,
        sourceUrl: URL
    ) throws -> [String: Data] {
        try Task.checkCancellation()
        let path = sourceUrl.standardizedFileURL.path(percentEncoded: false)
        if sourcePath != path {
            sourcePath = nil
            resources = [:]
            let loadedResources = try FoundryBridgeDecoder(limits: limits).allResourceData(sourceUrl: sourceUrl)
            resources = loadedResources
            sourcePath = path
        }
        var result: [String: Data] = [:]
        result.reserveCapacity(logicalPaths.count)
        for logicalPath in logicalPaths {
            try Task.checkCancellation()
            guard let data = resources[logicalPath] else {
                throw FoundryImportError.resourceUnavailable(logicalPath)
            }
            result[logicalPath] = data
        }
        return result
    }
}

// `FoundryBridgeDecoder` and the Bridge Decode Models now live in
// `FoundryVTTBridgeDecoding.swift`. See CODE_AUDIT §9.8.
