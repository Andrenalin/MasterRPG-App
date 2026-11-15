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
        await bridgeResourceCache.invalidate(sourceURL: URL(filePath: "/"))
        await zipDataSourceCache.invalidate(sourceURL: URL(filePath: "/"))
    }

    public func read(from url: URL) async throws -> FoundryVTTImportPackage {
        if url.lastPathComponent.lowercased().hasSuffix(".mrpgfoundry") {
            await bridgeResourceCache.invalidate(sourceURL: url)
        }
        await zipDataSourceCache.invalidate(sourceURL: url)
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
                    sourceURL: url
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
        from sourceURL: URL
    ) async throws -> FoundryPackageResourceData {
        let limits = limits
        let bridgeResourceCache = bridgeResourceCache
        let zipDataSourceCache = zipDataSourceCache
        // Structured and scope-balanced; cancellation propagates. See CODE_AUDIT_18 §4.4.
        return try await sourceURL.withSecurityScopedAccess { sourceURL in
            guard resource.location == .packaged,
                  let expectedSize = resource.byteCount,
                  let expectedSHA256 = resource.sha256 else {
                throw FoundryImportError.resourceUnavailable(resource.logicalPath)
            }
            let data: Data
            let lowercasedName = sourceURL.lastPathComponent.lowercased()
            if lowercasedName.hasSuffix(".mrpgfoundry") {
                let bridgeResources = try await bridgeResourceCache.resourceData(
                    logicalPaths: [resource.logicalPath],
                    sourceURL: sourceURL
                )
                guard let bridgeData = bridgeResources[resource.logicalPath] else {
                    throw FoundryImportError.resourceUnavailable(resource.logicalPath)
                }
                data = bridgeData
            } else if resource.packagePath == "universal-vtt/image"
                        || lowercasedName.hasSuffix(".uvtt")
                        || lowercasedName.hasSuffix(".dd2vtt") {
                data = try UniversalVTTReader.imageDataSynchronously(from: sourceURL, limits: limits)
            } else {
                let source = try await zipDataSourceCache.dataSource(for: sourceURL)
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

struct FoundryVTTDecoder {
    let limits: FoundryImportLimits

    func decode(from url: URL) throws -> FoundryVTTImportPackage {
        let source = try FoundryVTTDataSource(url: url, limits: limits)
        return try decode(source: source)
    }

    /// Decodes an already-parsed source. Split out of `decode(from:)` so a caller that needs
    /// the parsed source afterward (`FoundryVTTImportReader.read(from:)`, to hand its archive
    /// to `FoundrySystemPackageReader` without reparsing) can build it once and reuse it.
    func decode(source: FoundryVTTDataSource) throws -> FoundryVTTImportPackage {
        if source.selectedPath?.lowercased().hasSuffix(".mrpgfoundry") == true {
            return try FoundryBridgeDecoder(limits: limits).decodePackage(source: source)
        }
        let manifestSelection = try selectManifest(in: source)
        let manifest = try manifestSelection.map { try decodeManifest(path: $0.path, kind: $0.kind, source: source) }
        let kind = manifest?.kind ?? inferredPackageKind(source: source)
        let basePath = manifestSelection.map { String($0.path.dropLast($0.filename.count)) } ?? ""
        // The stable source scope is added by the domain mapper. An unmanifested transport name is
        // only a mutable presentation detail, so it must not enter the canonical Foundry ID.
        let packageID = manifest?.id ?? "unmanifested-source"

        var diagnostics: [FoundryImportDiagnostic] = []
        let specs = try collectionSpecs(
            manifest: manifest,
            manifestPath: manifestSelection?.path,
            basePath: basePath,
            source: source,
            diagnostics: &diagnostics
        )
        guard !specs.isEmpty else { throw FoundryImportError.unsupportedSource }

        var budget = FoundryVTTReadBudget()
        var collections: [FoundryDocumentCollection] = []
        for spec in specs {
            try Task.checkCancellation()
            do {
                let result = try decodeCollection(
                    spec,
                    packageKind: kind,
                    packageID: packageID,
                    source: source,
                    budget: &budget
                )
                collections.append(result.collection)
                diagnostics.append(contentsOf: result.diagnostics)
            } catch FoundryImportError.missingPack {
                diagnostics.append(FoundryImportDiagnostic(
                    severity: .warning,
                    code: "missing-collection",
                    message: "The declared Foundry collection \(spec.name) is not present.",
                    packName: spec.name
                ))
            }
        }
        guard !collections.isEmpty else { throw FoundryImportError.unsupportedSource }
        collections.sort { lhs, rhs in
            lhs.label == rhs.label ? lhs.id < rhs.id : lhs.label.localizedStandardCompare(rhs.label) == .orderedAscending
        }
        try FoundryVTTDocumentIdentityValidator.validate(collections)

        let assetPaths = FoundryAssetPathCollector.paths(in: collections.flatMap(\.documents).map(\.rawData)).sorted()
        let packageDirectory: String? = switch kind {
        case .system: "systems"
        case .module: "modules"
        case .world: "worlds"
        case .exportedDocument, .documentCollection: nil
        }
        let resources = try FoundryPackageResourceResolver.resolve(
            assetPaths: assetPaths,
            packageDirectory: packageDirectory,
            packageID: packageID,
            basePath: basePath,
            contains: { source.contains(path: $0) },
            data: { try source.data(forPath: $0) },
            limits: limits
        )
        var textPaths = Set(source.paths.filter { FoundryPackagePath.isLicensePath($0) })
        for language in manifest?.rawData["languages"]?.arrayValue ?? [] {
            guard let relativePath = language["path"]?.stringValue,
                  let path = try? FoundryPackagePath.join(basePath, relativePath),
                  source.contains(path: path) else { continue }
            textPaths.insert(path)
        }
        var textResources: [FoundryPackageTextResource] = []
        var totalTextResourceBytes = 0
        for path in textPaths.sorted() {
            try Task.checkCancellation()
            guard let data = try source.data(forPath: path) else { continue }
            let (nextTextResourceBytes, overflow) = totalTextResourceBytes.addingReportingOverflow(data.count)
            guard !overflow, nextTextResourceBytes <= limits.maximumRuleDataSize else {
                throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextTextResourceBytes)
            }
            totalTextResourceBytes = nextTextResourceBytes
            guard let content = String(data: data, encoding: .utf8) else { continue }
            textResources.append(FoundryPackageTextResource(path: path, content: content))
        }
        let statistics = FoundryVTTStatisticsBuilder.build(collections)
        diagnostics.append(FoundryImportDiagnostic(
            severity: .information,
            code: "documents-decoded",
            message: "Decoded \(statistics.topLevelDocumentCount) top-level and \(statistics.embeddedDocumentCount) embedded Foundry documents from \(statistics.collectionCount) collections."
        ))
        return FoundryVTTImportPackage(
            sourceSHA256: source.sourceSHA256,
            kind: kind,
            manifestPath: manifestSelection?.path,
            manifest: manifest,
            collections: collections,
            resources: resources,
            textResources: textResources,
            diagnostics: diagnostics,
            statistics: statistics
        )
    }
}

// MARK: - Manifest Selection & Decoding

private extension FoundryVTTDecoder {
    struct ManifestSelection {
        let path: String
        let filename: String
        let kind: FoundryVTTPackageKind
    }

    func selectManifest(in source: FoundryVTTDataSource) throws -> ManifestSelection? {
        let names: [(String, FoundryVTTPackageKind)] = [
            ("system.json", .system), ("module.json", .module), ("world.json", .world),
        ]
        if let selected = source.selectedPath,
           let pair = names.first(where: { selected.lowercased().hasSuffix($0.0) }) {
            return ManifestSelection(path: selected, filename: pair.0, kind: pair.1)
        }
        let candidates = source.paths.compactMap { path -> ManifestSelection? in
            guard let name = path.split(separator: "/").last?.lowercased(),
                  let pair = names.first(where: { $0.0 == name }) else { return nil }
            return ManifestSelection(path: path, filename: pair.0, kind: pair.1)
        }
        guard !candidates.isEmpty else { return nil }
        let minimumDepth = candidates.map { $0.path.split(separator: "/").count }.min() ?? 0
        let nearest = candidates.filter { $0.path.split(separator: "/").count == minimumDepth }
        guard nearest.count == 1 else { throw FoundryImportError.ambiguousManifest }
        return nearest[0]
    }

    func inferredPackageKind(source: FoundryVTTDataSource) -> FoundryVTTPackageKind {
        guard let selected = source.selectedPath else { return .documentCollection }
        return selected.lowercased().hasSuffix(".json") ? .exportedDocument : .documentCollection
    }

    func decodeManifest(
        path: String,
        kind: FoundryVTTPackageKind,
        source: FoundryVTTDataSource
    ) throws -> FoundryVTTPackageManifest {
        guard let data = try source.data(forPath: path) else { throw FoundryImportError.missingManifest }
        let raw = try FoundryJSONDecoding.decode(data, context: path)
        guard let object = raw.objectValue,
              let id = object["id"]?.stringValue, !id.isEmpty else {
            throw FoundryImportError.invalidManifest("The id field is missing.")
        }
        let title = object["title"]?.stringValue ?? object["name"]?.stringValue ?? id
        let compatibility = object["compatibility"]?.objectValue ?? [:]
        return FoundryVTTPackageManifest(
            kind: kind,
            id: id,
            title: title,
            descriptionHTML: object["description"]?.stringValue,
            version: object["version"]?.foundryScalarString,
            systemID: object["system"]?.stringValue,
            compatibility: FoundryCompatibility(
                minimum: compatibility["minimum"]?.foundryScalarString,
                verified: compatibility["verified"]?.foundryScalarString,
                maximum: compatibility["maximum"]?.foundryScalarString
            ),
            rawData: raw
        )
    }
}

// MARK: - Collection Discovery

struct FoundryVTTCollectionSpec {
    let id: String
    let name: String
    let label: String
    let path: String
    let declaredType: FoundryDocumentType
    let rawData: FoundryJSONValue?
}

private extension FoundryVTTDecoder {
    /// A realistic package has a few dozen collections. The count is capped so a crafted source
    /// with tens of thousands of bogus packs or directories cannot turn into that many collection
    /// decodes. See CODE_AUDIT_26 §7.2.
    static let maximumCollectionSpecs = 1_000

    func checkSpecCount(_ count: Int) throws {
        guard count <= min(limits.maximumDocumentCount, Self.maximumCollectionSpecs) else {
            throw FoundryImportError.tooManyDocuments(count)
        }
    }

    /// Whether `path` or one of its ancestor directories is in `declared`.
    static func isDeclared(_ path: String, in declared: Set<String>) -> Bool {
        if declared.contains(path) { return true }
        var components = path.split(separator: "/")
        while !components.isEmpty {
            if declared.contains(components.joined(separator: "/")) { return true }
            components.removeLast()
        }
        return false
    }

    func collectionSpecs(
        manifest: FoundryVTTPackageManifest?,
        manifestPath: String?,
        basePath: String,
        source: FoundryVTTDataSource,
        diagnostics: inout [FoundryImportDiagnostic]
    ) throws -> [FoundryVTTCollectionSpec] {
        if let selected = source.selectedPath,
           manifestPath == nil,
           selected.lowercased().hasSuffix(".mrpgfoundry") {
            return [FoundryVTTCollectionSpec(
                id: selected,
                name: URL(filePath: selected).deletingPathExtension().lastPathComponent,
                label: URL(filePath: selected).deletingPathExtension().lastPathComponent,
                path: selected,
                declaredType: .unknown,
                rawData: nil
            )]
        }

        var specs: [FoundryVTTCollectionSpec] = []
        if let rawPacks = manifest?.rawData["packs"] {
            let declarations: [(String?, FoundryJSONValue)]
            if let array = rawPacks.arrayValue {
                declarations = array.map { (nil, $0) }
            } else if let object = rawPacks.objectValue {
                declarations = object.keys.sorted().compactMap { key in object[key].map { (key, $0) } }
            } else {
                declarations = []
                diagnostics.append(FoundryImportDiagnostic(
                    severity: .warning,
                    code: "invalid-packs-declaration",
                    message: "The manifest packs declaration is not an array or object. Database files will still be discovered."
                ))
            }
            for (fallbackName, declaration) in declarations {
                guard let object = declaration.objectValue else { continue }
                let name = object["name"]?.stringValue ?? object["id"]?.stringValue ?? fallbackName ?? "pack-\(specs.count + 1)"
                let relativePath = object["path"]?.stringValue ?? "packs/\(name)"
                let path = try FoundryPackagePath.join(basePath, relativePath)
                let typeName = object["type"]?.stringValue
                    ?? object["documentName"]?.stringValue
                    ?? object["documentType"]?.stringValue
                specs.append(FoundryVTTCollectionSpec(
                    id: name,
                    name: name,
                    label: object["label"]?.stringValue ?? object["title"]?.stringValue ?? name,
                    path: path,
                    declaredType: FoundryDocumentType.inferred(from: typeName),
                    rawData: declaration
                ))
                // A tiny, well-formed manifest could otherwise declare millions of bogus
                // packs — each one going on to cost real work below (path resolution,
                // collection decoding) even after a fast per-lookup path. Fail fast
                // instead of materializing an unbounded spec list. See CODE_AUDIT §5.9.
                try checkSpecCount(specs.count)
            }
        }

        let selectedStandalone = source.selectedPath.flatMap { selected -> FoundryVTTCollectionSpec? in
            guard manifestPath == nil else { return nil }
            let lowercased = selected.lowercased()
            guard lowercased.hasSuffix(".json") || lowercased.hasSuffix(".db") else { return nil }
            let name = URL(filePath: selected).deletingPathExtension().lastPathComponent
            return FoundryVTTCollectionSpec(
                // A selected JSON/NeDB file is the source's sole collection. Keep its display name,
                // but do not let a Finder rename change every projected item UUID.
                id: "standalone",
                name: name,
                label: name,
                path: selected,
                declaredType: FoundryDocumentType.inferred(fromCollectionName: name),
                rawData: nil
            )
        }
        if let selectedStandalone { specs.append(selectedStandalone) }

        let declaredPaths = Set(specs.map(\.path))
        for path in source.paths where path.lowercased().hasSuffix(".db") {
            guard !declaredPaths.contains(path), !FoundryPackagePath.isManifest(path) else { continue }
            let name = URL(filePath: path).deletingPathExtension().lastPathComponent
            specs.append(FoundryVTTCollectionSpec(
                id: path,
                name: name,
                label: name,
                path: path,
                declaredType: .inferred(fromCollectionName: name),
                rawData: nil
            ))
            try checkSpecCount(specs.count)
        }

        let levelDBDirectories = Set(source.paths.compactMap { path -> String? in
            let lowercased = path.lowercased()
            let stem = URL(filePath: path).deletingPathExtension().lastPathComponent
            let isNumericLog = lowercased.hasSuffix(".log") && stem.allSatisfy(\.isNumber)
            guard lowercased.hasSuffix(".ldb") || lowercased.hasSuffix(".sst") || isNumericLog else { return nil }
            // `path` is a normalized package-relative path. URL(filePath:) resolves it
            // against the process working directory, which would turn the parent absolute and
            // make it impossible to match against `source.paths`.
            return path.split(separator: "/").dropLast().joined(separator: "/")
        })
        // The directories already declared, looked up with the directory and each of its
        // ancestors instead of testing every spec for every directory. See CODE_AUDIT_26 §7.2.
        var declaredDirectories = Set(specs.map { $0.path.hasSuffix("/") ? String($0.path.dropLast()) : $0.path })
        for path in levelDBDirectories.sorted() {
            guard !Self.isDeclared(path, in: declaredDirectories) else { continue }
            let name = URL(filePath: path).lastPathComponent
            declaredDirectories.insert(path)
            specs.append(FoundryVTTCollectionSpec(
                id: path.isEmpty && manifest == nil ? "standalone" : path,
                name: name,
                label: name,
                path: path,
                declaredType: .inferred(fromCollectionName: name),
                rawData: nil
            ))
            try checkSpecCount(specs.count)
        }

        if specs.isEmpty, manifest == nil {
            let likelyJSON = source.paths.filter { path in
                let name = URL(filePath: path).lastPathComponent.lowercased()
                guard name.hasSuffix(".json") else { return false }
                let stem = URL(filePath: name).deletingPathExtension().lastPathComponent
                return FoundryDocumentType.inferred(fromCollectionName: stem) != .unknown
                    || name.hasSuffix(".foundry.json")
            }
            for path in likelyJSON {
                let name = URL(filePath: path).deletingPathExtension().lastPathComponent
                specs.append(FoundryVTTCollectionSpec(
                    id: path,
                    name: name,
                    label: name,
                    path: path,
                    declaredType: .inferred(fromCollectionName: name),
                    rawData: nil
                ))
            }
        }
        var seen = Set<String>()
        return specs.filter { seen.insert($0.path).inserted }
    }

    func decodeCollection(
        _ spec: FoundryVTTCollectionSpec,
        packageKind: FoundryVTTPackageKind,
        packageID: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        let lowercased = spec.path.lowercased()
        if lowercased.hasSuffix(".db") {
            return try decodeLegacyDatabase(
                spec,
                packageKind: packageKind,
                packageID: packageID,
                source: source,
                budget: &budget
            )
        }
        if lowercased.hasSuffix(".json") {
            return try decodeJSONCollection(
                spec,
                packageKind: packageKind,
                packageID: packageID,
                source: source,
                budget: &budget
            )
        }
        return try decodeLevelDBCollection(
            spec,
            packageKind: packageKind,
            packageID: packageID,
            source: source,
            budget: &budget
        )
    }
}

// `FoundryLevelDBLiveFiles`, the LevelDB-specific `FoundryVTTDecoder` extension
// (decodeLevelDBCollection/decodeLegacyDatabase/decodeJSONCollection), and
// `FoundryLevelDBRecordMerger` now live in `FoundryVTTDecoder+CollectionDecoding.swift`.
// See CODE_AUDIT §9.8.

// MARK: - Document Tree Assembly

private struct FoundryVTTRecordComponent: Hashable {
    let collection: String
    let id: String
    let documentType: FoundryDocumentType
}

struct FoundryVTTDocumentDecoder {
    let packageKind: FoundryVTTPackageKind
    let packageID: String
    let spec: FoundryVTTCollectionSpec
    let limits: FoundryImportLimits

    func decodeLevelDB(
        _ records: [FoundryLevelDBRecord],
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        var rawByPath: [[FoundryVTTRecordComponent]: FoundryJSONValue] = [:]
        var folderRaws: [(String, FoundryJSONValue)] = []
        var invalidKeys: [String] = []
        for record in records {
            try Task.checkCancellation()
            guard let path = FoundryVTTLevelDBKey.parse(record.key), !path.isEmpty else {
                invalidKeys.append(record.key)
                continue
            }
            do {
                let raw = try FoundryJSONDecoding.decode(record.value, context: record.key)
                if path.count == 1, path[0].documentType == .folder {
                    folderRaws.append((path[0].id, raw))
                } else {
                    rawByPath[path] = raw
                }
            } catch {
                invalidKeys.append(record.key)
            }
        }

        var childrenByParent: [[FoundryVTTRecordComponent]: [[FoundryVTTRecordComponent]]] = [:]
        for path in rawByPath.keys where path.count > 1 {
            childrenByParent[Array(path.dropLast()), default: []].append(path)
        }
        let topPaths = rawByPath.keys.filter { $0.count == 1 }.sorted(by: FoundryVTTLevelDBKey.lessThan)
        var documents: [FoundryDocument] = []
        for path in topPaths {
            guard let raw = rawByPath[path] else { continue }
            documents.append(try decodeDocument(
                raw: raw,
                fallbackID: path.last?.id ?? "document",
                explicitType: path.last?.documentType ?? spec.declaredType,
                parentCanonicalID: nil,
                externalPath: path,
                rawByPath: rawByPath,
                childrenByParent: childrenByParent,
                depth: 0,
                budget: &budget
            ))
        }
        var folders = folderRaws.map { pair in
            decodeFolder(fallbackID: pair.0, raw: pair.1)
        }
        folders.sort { lhs, rhs in
            lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name
        }
        let diagnostics = invalidKeys.isEmpty ? [] : [FoundryImportDiagnostic(
            severity: .warning,
            code: "unrecognized-leveldb-records",
            message: "Skipped \(invalidKeys.count) LevelDB records whose key hierarchy or JSON value was invalid.",
            packName: spec.name
        )]
        return (makeCollection(documents: documents, folders: folders), diagnostics)
    }

    func decodeRawDocuments(
        _ raws: [(String, FoundryJSONValue)],
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        var documents: [FoundryDocument] = []
        var folders: [FoundryDocumentFolder] = []
        var invalidCount = 0
        for (fallbackID, raw) in raws.sorted(by: { $0.0 < $1.0 }) {
            guard raw.objectValue != nil else {
                invalidCount += 1
                continue
            }
            let inferredType = FoundryDocumentType.inferred(from: raw, fallback: spec.declaredType)
            if inferredType == .folder {
                folders.append(decodeFolder(fallbackID: fallbackID, raw: raw))
            } else {
                documents.append(try decodeDocument(
                    raw: raw,
                    fallbackID: fallbackID,
                    explicitType: inferredType,
                    parentCanonicalID: nil,
                    externalPath: nil,
                    rawByPath: [:],
                    childrenByParent: [:],
                    depth: 0,
                    budget: &budget
                ))
            }
        }
        let diagnostics = invalidCount == 0 ? [] : [FoundryImportDiagnostic(
            severity: .warning,
            code: "invalid-json-documents",
            message: "Skipped \(invalidCount) non-object values in \(spec.name).",
            packName: spec.name
        )]
        return (makeCollection(documents: documents, folders: folders), diagnostics)
    }
}

extension FoundryVTTDocumentDecoder {
    func makeCollection(
        documents: [FoundryDocument],
        folders: [FoundryDocumentFolder]
    ) -> FoundryDocumentCollection {
        FoundryDocumentCollection(
            id: spec.id,
            name: spec.name,
            label: spec.label,
            sourcePath: spec.path,
            declaredDocumentType: spec.declaredType,
            documents: documents.sorted(by: FoundryDocument.foundrySort),
            folders: folders.sorted { lhs, rhs in lhs.name == rhs.name ? lhs.id < rhs.id : lhs.name < rhs.name },
            rawData: spec.rawData
        )
    }

    func decodeFolder(fallbackID: String, raw: FoundryJSONValue) -> FoundryDocumentFolder {
        let documentID = raw["_id"]?.stringValue ?? raw["id"]?.stringValue ?? fallbackID
        return FoundryDocumentFolder(
            id: canonicalTopLevelID(type: .folder, documentID: documentID),
            documentID: documentID,
            name: raw["name"]?.stringValue ?? documentID,
            parentID: raw["folder"]?.foundryIdentifier ?? raw["parent"]?.foundryIdentifier,
            documentType: .inferred(from: raw["type"]?.stringValue),
            sort: raw["sort"]?.integerValue,
            rawData: raw
        )
    }

    private func decodeDocument(
        raw: FoundryJSONValue,
        fallbackID: String,
        explicitType: FoundryDocumentType,
        parentCanonicalID: String?,
        externalPath: [FoundryVTTRecordComponent]?,
        rawByPath: [[FoundryVTTRecordComponent]: FoundryJSONValue],
        childrenByParent: [[FoundryVTTRecordComponent]: [[FoundryVTTRecordComponent]]],
        depth: Int,
        budget: inout FoundryVTTReadBudget
    ) throws -> FoundryDocument {
        guard depth < 64 else {
            throw FoundryImportError.invalidDocument(pack: spec.name, key: "embedded hierarchy exceeds 64 levels")
        }
        try budget.includeRecord(limits: limits)
        let documentID = raw["_id"]?.stringValue ?? raw["id"]?.stringValue ?? fallbackID
        let type = explicitType == .unknown
            ? FoundryDocumentType.inferred(from: raw, fallback: spec.declaredType)
            : explicitType
        let canonicalID = parentCanonicalID.map {
            "\($0)/\(Self.component(type.rawValue))/\(Self.component(documentID))"
        } ?? canonicalTopLevelID(type: type, documentID: documentID)

        var embedded: [FoundryDocument] = []
        var externalIdentities = Set<String>()
        if let externalPath {
            for childPath in (childrenByParent[externalPath] ?? []).sorted(by: FoundryVTTLevelDBKey.lessThan) {
                guard let component = childPath.last, let childRaw = rawByPath[childPath] else { continue }
                externalIdentities.insert("\(component.documentType.rawValue):\(component.id)")
                embedded.append(try decodeDocument(
                    raw: childRaw,
                    fallbackID: component.id,
                    explicitType: component.documentType,
                    parentCanonicalID: canonicalID,
                    externalPath: childPath,
                    rawByPath: rawByPath,
                    childrenByParent: childrenByParent,
                    depth: depth + 1,
                    budget: &budget
                ))
            }
        }
        for candidate in FoundryVTTEmbeddedExtractor.documents(in: raw, parentType: type) {
            let candidateID = candidate.raw["_id"]?.stringValue
                ?? candidate.raw["id"]?.stringValue
                ?? "embedded-\(embedded.count + 1)"
            guard !externalIdentities.contains("\(candidate.type.rawValue):\(candidateID)") else { continue }
            embedded.append(try decodeDocument(
                raw: candidate.raw,
                fallbackID: candidateID,
                explicitType: candidate.type,
                parentCanonicalID: canonicalID,
                externalPath: nil,
                rawByPath: [:],
                childrenByParent: [:],
                depth: depth + 1,
                budget: &budget
            ))
        }

        let knownFields = FoundryVTTKnownFields.names(for: type)
        let unknownFields = raw.objectValue?.keys.filter { !knownFields.contains($0) }.sorted() ?? []
        return FoundryDocument(
            id: canonicalID,
            documentID: documentID,
            documentType: type,
            subtype: raw["type"]?.stringValue.flatMap {
                FoundryDocumentType.inferred(from: $0) == .unknown ? $0 : nil
            },
            name: raw["name"]?.stringValue ?? documentID,
            folderID: raw["folder"]?.foundryIdentifier,
            sort: raw["sort"]?.integerValue,
            imagePath: raw["img"]?.stringValue ?? raw["image"]?.stringValue ?? raw.value(at: "texture.src")?.stringValue,
            descriptionHTML: FoundryVTTDescriptionFinder.description(in: raw),
            parentID: parentCanonicalID,
            embeddedDocuments: embedded.sorted(by: FoundryDocument.foundrySort),
            references: FoundryReferenceDecoder.decode(in: raw),
            unknownFieldNames: unknownFields,
            rawData: raw
        )
    }

    func canonicalTopLevelID(type: FoundryDocumentType, documentID: String) -> String {
        "foundry://\(packageKind.rawValue)/\(Self.component(packageID))/collection/\(Self.component(spec.id))/\(Self.component(type.rawValue))/\(Self.component(documentID))"
    }

    static func component(_ value: String) -> String {
        FoundryPackagePath.encodedComponent(value)
    }
}

// MARK: - LevelDB Key Parsing

private enum FoundryVTTLevelDBKey {
    static func parse(_ key: String) -> [FoundryVTTRecordComponent]? {
        guard key.hasPrefix("!"),
              let namespaceEnd = key.dropFirst().firstIndex(of: "!") else { return nil }
        let namespace = key[key.index(after: key.startIndex)..<namespaceEnd]
        let identifiersStart = key.index(after: namespaceEnd)
        let identifiers = key[identifiersStart...]
        let collections = namespace.split(separator: ".").map(String.init)
        let ids = identifiers.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard !collections.isEmpty, collections.count == ids.count,
              ids.allSatisfy({ !$0.isEmpty }) else { return nil }
        var result: [FoundryVTTRecordComponent] = []
        for (collection, id) in zip(collections, ids) {
            let parentType = result.last?.documentType
            let type = FoundryDocumentType.inferred(
                fromCollectionName: collection,
                embeddedIn: parentType
            )
            result.append(FoundryVTTRecordComponent(collection: collection, id: id, documentType: type))
        }
        return result
    }

    static func lessThan(
        _ lhs: [FoundryVTTRecordComponent],
        _ rhs: [FoundryVTTRecordComponent]
    ) -> Bool {
        let left = lhs.map { "\($0.collection):\($0.id)" }.joined(separator: "/")
        let right = rhs.map { "\($0.collection):\($0.id)" }.joined(separator: "/")
        return left < right
    }
}

// MARK: - Document Type Inference

extension FoundryDocumentType {
    static func inferred(from value: String?) -> Self {
        guard let value else { return .unknown }
        let key = value.lowercased().filter { $0.isLetter || $0.isNumber }
        return canonicalTypes[key] ?? .unknown
    }

    static func inferred(fromCollectionName value: String) -> Self {
        let key = value.lowercased().filter { $0.isLetter || $0.isNumber }
        if let exact = collectionTypes[key] { return exact }
        let tokens = value.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
        if tokens.first == "fvtt", tokens.count > 1 {
            let exportedType = inferred(from: tokens[1])
            if exportedType != .unknown { return exportedType }
        }
        return inferred(from: value)
    }

    static func inferred(fromCollectionName value: String, embeddedIn parent: Self?) -> Self {
        let key = value.lowercased().filter { $0.isLetter || $0.isNumber }
        if parent == .cards, key == "cards" { return .card }
        if parent == .playlist, key == "sounds" { return .playlistSound }
        if (parent == .scene || parent == .level), key == "sounds" { return .ambientSound }
        if parent == .scene, key == "levels" { return .level }
        return inferred(fromCollectionName: value)
    }

    static func inferred(from raw: FoundryJSONValue, fallback: Self) -> Self {
        let candidates = [
            raw["documentName"]?.stringValue,
            raw["documentType"]?.stringValue,
            raw.value(at: "_stats.documentName")?.stringValue,
        ]
        for candidate in candidates {
            let type = inferred(from: candidate)
            if type != .unknown { return type }
        }
        let explicitType = inferred(from: raw["type"]?.stringValue)
        if explicitType != .unknown { return explicitType }
        if fallback != .unknown { return fallback }
        guard let object = raw.objectValue else { return .unknown }
        if object["tokens"] != nil || object["walls"] != nil || object["background"] != nil { return .scene }
        if object["pages"] != nil { return .journalEntry }
        if object["results"] != nil && (object["formula"] != nil || object["replacement"] != nil) { return .rollTable }
        if object["sounds"] != nil && object["mode"] != nil { return .playlist }
        if object["cards"] != nil && (object["drawn"] != nil || object["pile"] != nil) { return .cards }
        if object["combatants"] != nil && object["round"] != nil { return .combat }
        if object["items"] != nil && object["system"] != nil { return .actor }
        return .unknown
    }

    static let canonicalTypes: [String: Self] = [
        "actor": .actor, "item": .item, "scene": .scene, "level": .level,
        "journalentry": .journalEntry, "journalentrypage": .journalEntryPage,
        "rolltable": .rollTable, "tableresult": .tableResult,
        "playlist": .playlist, "playlistsound": .playlistSound,
        "cards": .cards, "card": .card, "adventure": .adventure,
        "folder": .folder, "activeeffect": .activeEffect,
        "token": .token, "tokendocument": .token,
        "wall": .wall, "walldocument": .wall,
        "ambientlight": .ambientLight, "ambientlightdocument": .ambientLight,
        "ambientsound": .ambientSound, "ambientsounddocument": .ambientSound,
        "tile": .tile, "tiledocument": .tile,
        "drawing": .drawing, "drawingdocument": .drawing,
        "note": .note, "notedocument": .note,
        "region": .region, "regiondocument": .region,
        "combat": .combat, "combatant": .combatant,
        "macro": .macro, "chatmessage": .chatMessage, "message": .chatMessage,
        "user": .user,
    ]

    static let collectionTypes: [String: Self] = canonicalTypes.merging([
        "actors": .actor, "items": .item, "scenes": .scene, "levels": .level,
        "journal": .journalEntry, "journals": .journalEntry,
        "journalentries": .journalEntry, "pages": .journalEntryPage,
        "tables": .rollTable, "rolltables": .rollTable, "results": .tableResult,
        "playlists": .playlist, "sounds": .playlistSound,
        "cards": .cards, "carddocuments": .card,
        "adventures": .adventure, "folders": .folder,
        "effects": .activeEffect,
        "tokens": .token, "walls": .wall, "lights": .ambientLight,
        "ambientsounds": .ambientSound, "soundsdocuments": .ambientSound,
        "tiles": .tile, "drawings": .drawing, "notes": .note, "regions": .region,
        "combats": .combat, "combatants": .combatant,
        "macros": .macro, "messages": .chatMessage, "chatmessages": .chatMessage,
        "users": .user,
    ], uniquingKeysWith: { _, new in new })
}

// MARK: - Embedded Document Extraction

private enum FoundryVTTEmbeddedExtractor {
    struct Candidate {
        let type: FoundryDocumentType
        let raw: FoundryJSONValue
    }

    static func documents(in raw: FoundryJSONValue, parentType: FoundryDocumentType) -> [Candidate] {
        guard let object = raw.objectValue else { return [] }
        var mappings = standardMappings[parentType] ?? [:]
        if parentType == .adventure {
            mappings.merge(adventureMappings, uniquingKeysWith: { current, _ in current })
        }
        var result: [Candidate] = []
        for key in mappings.keys.sorted() {
            guard let values = object[key]?.arrayValue, let type = mappings[key] else { continue }
            for value in values where value.objectValue != nil {
                result.append(Candidate(type: type, raw: value))
            }
        }
        return result
    }

    static let standardMappings: [FoundryDocumentType: [String: FoundryDocumentType]] = [
        .actor: ["items": .item, "effects": .activeEffect],
        .item: ["effects": .activeEffect],
        .scene: [
            "levels": .level, "tokens": .token, "walls": .wall, "lights": .ambientLight,
            "sounds": .ambientSound, "tiles": .tile, "drawings": .drawing,
            "notes": .note, "regions": .region,
        ],
        .level: [
            "tokens": .token, "walls": .wall, "lights": .ambientLight,
            "sounds": .ambientSound, "tiles": .tile, "drawings": .drawing,
            "notes": .note, "regions": .region,
        ],
        .journalEntry: ["pages": .journalEntryPage],
        .rollTable: ["results": .tableResult],
        .playlist: ["sounds": .playlistSound],
        .cards: ["cards": .card],
        .combat: ["combatants": .combatant],
    ]

    static let adventureMappings: [String: FoundryDocumentType] = [
        "actors": .actor, "items": .item, "scenes": .scene,
        "journal": .journalEntry, "journals": .journalEntry,
        "journalEntries": .journalEntry, "tables": .rollTable,
        "rollTables": .rollTable, "playlists": .playlist, "cards": .cards,
        "combats": .combat, "macros": .macro, "folders": .folder,
    ]
}

// MARK: - Known Field Tracking

private enum FoundryVTTKnownFields {
    static let base = Set([
        "_id", "id", "_key", "_stats", "name", "type", "documentName", "documentType",
        "folder", "sort", "ownership", "permission", "flags", "system", "img", "image",
        "description", "content", "text", "effects",
    ])

    static func names(for type: FoundryDocumentType) -> Set<String> {
        base.union(typeFields[type] ?? [])
    }

    static let typeFields: [FoundryDocumentType: Set<String>] = [
        .actor: ["items", "prototypeToken"],
        .item: ["effects"],
        .scene: [
            "active", "navigation", "navOrder", "background", "foreground", "thumb",
            "width", "height", "padding", "initial", "initialLevel", "backgroundColor", "grid", "tokenVision",
            "fog", "fogExploration", "globalLight", "globalLightThreshold", "darkness",
            "environment", "weather", "levels", "tokens", "walls", "lights", "sounds", "tiles",
            "drawings", "notes", "regions", "playlist", "playlistSound",
        ],
        .level: [
            "background", "elevation", "fog", "foreground", "textures", "visibility",
            "tokens", "walls", "lights", "sounds", "tiles", "drawings", "notes", "regions",
        ],
        .journalEntry: ["pages"],
        .journalEntryPage: ["title", "src", "video", "image", "text"],
        .rollTable: ["formula", "replacement", "displayRoll", "results"],
        .tableResult: ["range", "drawn", "weight", "documentCollection", "documentId"],
        .playlist: ["mode", "playing", "fade", "seed", "sounds"],
        .playlistSound: ["path", "volume", "repeat", "channel", "playing", "pausedTime"],
        .cards: ["cards", "displayCount", "pile", "hands", "drawn"],
        .card: ["faces", "back", "face", "drawn", "origin"],
        .adventure: [
            "actors", "items", "scenes", "journal", "journals", "journalEntries", "tables",
            "rollTables", "playlists", "cards", "combats", "macros", "folders",
        ],
        .combat: ["scene", "active", "round", "turn", "combatants"],
        .folder: ["parent", "sorting", "color"],
    ]
}

// MARK: - Description Extraction

private enum FoundryVTTDescriptionFinder {
    static func description(in raw: FoundryJSONValue) -> String? {
        let candidates = [
            raw.value(at: "text.content"), raw["content"],
            raw.value(at: "system.description.value"), raw.value(at: "system.description"),
            raw["description"],
        ]
        return candidates.compactMap { $0?.stringValue }.first
    }
}

// MARK: - Document Sorting

private extension FoundryDocument {
    static func foundrySort(_ lhs: Self, _ rhs: Self) -> Bool {
        let leftSort = lhs.sort ?? 0
        let rightSort = rhs.sort ?? 0
        if leftSort != rightSort { return leftSort < rightSort }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id < rhs.id
    }
}

// MARK: - JSON Value & Data Helpers
//
// `FoundryPackagePath` (path utilities) and `FoundryJSONDecoding` (JSON decoding) now live in
// the shared `FoundryPackageResolution.swift`, used by both this reader and
// `FoundrySystemPackageReader`. See CODE_AUDIT §9.2, §9.3.

extension FoundryJSONValue {
    var foundryScalarString: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .unsignedInteger(let value): String(value)
        case .number(let value): String(value)
        default: nil
        }
    }

    var foundryIdentifier: String? {
        stringValue ?? self["_id"]?.stringValue ?? self["id"]?.stringValue
    }
}

extension Data.SubSequence {
    func foundryTrimmingASCIIWhitespace() -> Self {
        var lower = startIndex
        var upper = endIndex
        while lower < upper, [0x20, 0x09, 0x0d].contains(self[lower]) { formIndex(after: &lower) }
        while lower < upper {
            let previous = index(before: upper)
            guard [0x20, 0x09, 0x0d].contains(self[previous]) else { break }
            upper = previous
        }
        return self[lower..<upper]
    }
}

// MARK: - Document Identity Validation

enum FoundryVTTDocumentIdentityValidator {
    static func validate(_ collections: [FoundryDocumentCollection]) throws {
        var sourceByCanonicalID: [String: String] = [:]

        func visit(_ document: FoundryDocument, collection: FoundryDocumentCollection) throws {
            if let firstSource = sourceByCanonicalID[document.id] {
                throw FoundryImportError.invalidDocument(
                    pack: collection.name,
                    key: "duplicate canonical identifier \(document.id) (already present in \(firstSource))"
                )
            }
            sourceByCanonicalID[document.id] = collection.name
            for child in document.embeddedDocuments {
                try visit(child, collection: collection)
            }
        }

        for collection in collections {
            for document in collection.documents {
                try visit(document, collection: collection)
            }
        }
    }
}

// MARK: - Import Statistics

enum FoundryVTTStatisticsBuilder {
    static func build(_ collections: [FoundryDocumentCollection]) -> FoundryVTTImportStatistics {
        var embeddedCount = 0
        var unknownFieldCount = 0
        var counts: [String: Int] = [:]
        func visit(_ document: FoundryDocument, isTopLevel: Bool) {
            counts[document.documentType.rawValue, default: 0] += 1
            unknownFieldCount += document.unknownFieldNames.count
            if !isTopLevel { embeddedCount += 1 }
            for child in document.embeddedDocuments { visit(child, isTopLevel: false) }
        }
        for document in collections.flatMap(\.documents) { visit(document, isTopLevel: true) }
        return FoundryVTTImportStatistics(
            collectionCount: collections.count,
            topLevelDocumentCount: collections.reduce(0) { $0 + $1.documents.count },
            embeddedDocumentCount: embeddedCount,
            folderCount: collections.reduce(0) { $0 + $1.folders.count },
            unknownFieldCount: unknownFieldCount,
            documentCounts: counts
        )
    }
}

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

    func invalidate(sourceURL _: URL) {
        sourcePath = nil
        dataSource = nil
    }

    func dataSource(for sourceURL: URL) throws -> FoundryVTTDataSource {
        try Task.checkCancellation()
        let path = sourceURL.standardizedFileURL.path(percentEncoded: false)
        if sourcePath == path, let dataSource {
            return dataSource
        }
        let created = try FoundryVTTDataSource(url: sourceURL, limits: limits)
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

    func invalidate(sourceURL _: URL) {
        sourcePath = nil
        resources = [:]
    }

    func resourceData(
        logicalPaths: Set<String>,
        sourceURL: URL
    ) throws -> [String: Data] {
        try Task.checkCancellation()
        let path = sourceURL.standardizedFileURL.path(percentEncoded: false)
        if sourcePath != path {
            sourcePath = nil
            resources = [:]
            let loadedResources = try FoundryBridgeDecoder(limits: limits).allResourceData(sourceURL: sourceURL)
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
