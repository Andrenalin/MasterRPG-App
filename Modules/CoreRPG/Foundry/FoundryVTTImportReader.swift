// @copyright André Trettin

import CryptoKit
import Foundation

/// Reads Foundry VTT system, module, world, compendium, and exported-document artifacts.
///
/// This is a data transport only: JavaScript is never evaluated and HTML is retained as text.
public struct FoundryVTTImportReader: Sendable {
    public let limits: FoundryImportLimits
    private let bridgeResourceCache: FoundryBridgeResourceCache

    public init(limits: FoundryImportLimits = .default) {
        self.limits = limits
        bridgeResourceCache = FoundryBridgeResourceCache(limits: limits)
    }

    public func read(from url: URL) async throws -> FoundryVTTImportPackage {
        if url.lastPathComponent.lowercased().hasSuffix(".mrpgfoundry") {
            await bridgeResourceCache.invalidate(sourceURL: url)
        }
        let limits = limits
        let task = Task.detached(priority: .userInitiated) {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
            }
            try Task.checkCancellation()
            return try FoundryVTTDecoder(limits: limits).decode(from: url)
        }
        var package = try await withTaskCancellationHandler {
            let decoded = try await task.value
            try Task.checkCancellation()
            return decoded
        } onCancel: {
            task.cancel()
        }

        if package.kind == .system {
            do {
                let rulePackage = try await FoundrySystemPackageReader(limits: limits).read(from: url)
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
        let task = Task.detached(priority: .userInitiated) {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope { url.stopAccessingSecurityScopedResource() }
            }
            let source = try FoundryVTTDataSource(url: url, limits: limits)
            if let expectedSHA256 = package.sourceSHA256,
               source.sourceSHA256 != expectedSHA256 {
                throw FoundryImportError.sourceMismatch
            }
            if let manifestPath = package.manifestPath,
               let expectedManifest = package.manifest?.rawData {
                guard let data = try source.data(forPath: manifestPath),
                      try FoundryVTTRawJSON.decode(data, context: manifestPath) == expectedManifest else {
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
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            task.cancel()
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
        let task = Task.detached(priority: .userInitiated) {
            let hasSecurityScope = sourceURL.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope { sourceURL.stopAccessingSecurityScopedResource() }
            }
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
                let source = try FoundryVTTDataSource(url: sourceURL, limits: limits)
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
        return try await withTaskCancellationHandler {
            let result = try await task.value
            try Task.checkCancellation()
            return result
        } onCancel: {
            task.cancel()
        }
    }
}

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

private struct FoundryVTTDecoder {
    let limits: FoundryImportLimits

    func decode(from url: URL) throws -> FoundryVTTImportPackage {
        let source = try FoundryVTTDataSource(url: url, limits: limits)
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

        let assetPaths = FoundryVTTAssetCollector.paths(in: collections).sorted()
        let resources = try FoundryVTTResourceResolver.resolve(
            assetPaths: assetPaths,
            kind: kind,
            packageID: packageID,
            basePath: basePath,
            source: source,
            limits: limits
        )
        var textPaths = Set(source.paths.filter { FoundryVTTPath.isLicensePath($0) })
        for language in manifest?.rawData["languages"]?.arrayValue ?? [] {
            guard let relativePath = language["path"]?.stringValue,
                  let path = try? FoundryVTTPath.join(basePath, relativePath),
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
        let raw = try FoundryVTTRawJSON.decode(data, context: path)
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

private struct FoundryVTTCollectionSpec {
    let id: String
    let name: String
    let label: String
    let path: String
    let declaredType: FoundryDocumentType
    let rawData: FoundryJSONValue?
}

private extension FoundryVTTDecoder {
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
                name: URL(fileURLWithPath: selected).deletingPathExtension().lastPathComponent,
                label: URL(fileURLWithPath: selected).deletingPathExtension().lastPathComponent,
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
                let path = try FoundryVTTPath.join(basePath, relativePath)
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
                // instead of materializing an unbounded spec list. See CODE_AUDIT §6.5.
                guard specs.count <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(specs.count)
                }
            }
        }

        let selectedStandalone = source.selectedPath.flatMap { selected -> FoundryVTTCollectionSpec? in
            guard manifestPath == nil else { return nil }
            let lowercased = selected.lowercased()
            guard lowercased.hasSuffix(".json") || lowercased.hasSuffix(".db") else { return nil }
            let name = URL(fileURLWithPath: selected).deletingPathExtension().lastPathComponent
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
            guard !declaredPaths.contains(path), !FoundryVTTPath.isManifest(path) else { continue }
            let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            specs.append(FoundryVTTCollectionSpec(
                id: path,
                name: name,
                label: name,
                path: path,
                declaredType: .inferred(fromCollectionName: name),
                rawData: nil
            ))
        }

        let levelDBDirectories = Set(source.paths.compactMap { path -> String? in
            let lowercased = path.lowercased()
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            let isNumericLog = lowercased.hasSuffix(".log") && stem.allSatisfy(\.isNumber)
            guard lowercased.hasSuffix(".ldb") || lowercased.hasSuffix(".sst") || isNumericLog else { return nil }
            // `path` is a normalized package-relative path. URL(fileURLWithPath:) resolves it
            // against the process working directory, which would turn the parent absolute and
            // make it impossible to match against `source.paths`.
            return path.split(separator: "/").dropLast().joined(separator: "/")
        })
        for path in levelDBDirectories.sorted() {
            let isAlreadyDeclared = specs.contains { spec in
                spec.path == path || path.hasPrefix(spec.path.hasSuffix("/") ? spec.path : spec.path + "/")
            }
            guard !isAlreadyDeclared else { continue }
            let name = URL(fileURLWithPath: path).lastPathComponent
            specs.append(FoundryVTTCollectionSpec(
                id: path.isEmpty && manifest == nil ? "standalone" : path,
                name: name,
                label: name,
                path: path,
                declaredType: .inferred(fromCollectionName: name),
                rawData: nil
            ))
        }

        if specs.isEmpty, manifest == nil {
            let likelyJSON = source.paths.filter { path in
                let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
                guard name.hasSuffix(".json") else { return false }
                let stem = URL(fileURLWithPath: name).deletingPathExtension().lastPathComponent
                return FoundryDocumentType.inferred(fromCollectionName: stem) != .unknown
                    || name.hasSuffix(".foundry.json")
            }
            for path in likelyJSON {
                let name = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
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

private struct FoundryVTTReadBudget {
    var encodedBytes = 0
    var decodedBytes = 0
    var recordCount = 0

    mutating func includeEncoded(_ count: Int, limits: FoundryImportLimits) throws {
        let (next, overflow) = encodedBytes.addingReportingOverflow(count)
        guard !overflow, next <= limits.maximumRuleDataSize else {
            throw FoundryImportError.fileTooLarge(overflow ? Int.max : next)
        }
        encodedBytes = next
    }

    mutating func includeDecoded(_ count: Int, limits: FoundryImportLimits) throws {
        let (next, overflow) = decodedBytes.addingReportingOverflow(count)
        guard !overflow, next <= limits.maximumRuleDataSize else {
            throw FoundryImportError.fileTooLarge(overflow ? Int.max : next)
        }
        decodedBytes = next
    }

    mutating func includeRecord(limits: FoundryImportLimits) throws {
        let (next, overflow) = recordCount.addingReportingOverflow(1)
        guard !overflow, next <= limits.maximumDocumentCount else {
            throw FoundryImportError.tooManyDocuments(overflow ? Int.max : next)
        }
        recordCount = next
    }
}

private struct FoundryLevelDBLiveFiles {
    let tables: [String]
    let logs: [String]
}

private extension FoundryVTTDecoder {
    func decodeLevelDBCollection(
        _ spec: FoundryVTTCollectionSpec,
        packageKind: FoundryVTTPackageKind,
        packageID: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        let prefix = spec.path.isEmpty ? "" : (spec.path.hasSuffix("/") ? spec.path : spec.path + "/")
        let discoveredTablePaths = source.paths.filter { path in
            let lowercased = path.lowercased()
            return (lowercased.hasSuffix(".ldb") || lowercased.hasSuffix(".sst"))
                && (prefix.isEmpty || path.hasPrefix(prefix))
        }.sorted()
        let discoveredLogPaths = source.paths.filter { path in
            guard path.lowercased().hasSuffix(".log"), prefix.isEmpty || path.hasPrefix(prefix) else { return false }
            return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.allSatisfy(\.isNumber)
        }.sorted()
        guard !discoveredTablePaths.isEmpty || !discoveredLogPaths.isEmpty else {
            throw FoundryImportError.missingPack(spec.name)
        }
        let liveFiles = try liveLevelDBPaths(
            discoveredTables: discoveredTablePaths,
            discoveredLogs: discoveredLogPaths,
            prefix: prefix,
            packName: spec.name,
            source: source,
            budget: &budget
        )

        var records: [FoundryLevelDBRecord] = []
        for path in liveFiles.tables {
            try Task.checkCancellation()
            guard let data = try source.data(forPath: path) else { continue }
            try budget.includeEncoded(data.count, limits: limits)
            let decoded = try FoundryLevelDBTableReader(limits: limits).records(in: data)
            for record in decoded {
                try budget.includeDecoded(record.key.utf8.count + record.value.count + 9, limits: limits)
            }
            let (nextCount, overflow) = records.count.addingReportingOverflow(decoded.count)
            guard !overflow, nextCount <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(overflow ? Int.max : nextCount)
            }
            records.append(contentsOf: decoded)
        }
        for path in liveFiles.logs {
            try Task.checkCancellation()
            guard let data = try source.data(forPath: path) else { continue }
            try budget.includeEncoded(data.count, limits: limits)
            let decoded = try FoundryLevelDBWriteAheadLogReader(limits: limits).records(in: data, path: path)
            for record in decoded {
                try budget.includeDecoded(record.key.utf8.count + record.value.count + 9, limits: limits)
            }
            let (nextCount, overflow) = records.count.addingReportingOverflow(decoded.count)
            guard !overflow, nextCount <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(overflow ? Int.max : nextCount)
            }
            records.append(contentsOf: decoded)
        }
        let current = try FoundryLevelDBRecordMerger.currentRecords(records)
        return try FoundryVTTDocumentDecoder(
            packageKind: packageKind,
            packageID: packageID,
            spec: spec,
            limits: limits
        ).decodeLevelDB(current, budget: &budget)
    }

    func liveLevelDBPaths(
        discoveredTables: [String],
        discoveredLogs: [String],
        prefix: String,
        packName: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> FoundryLevelDBLiveFiles {
        let currentPath = source.paths.first { path in
            path == prefix + "CURRENT" || path == prefix + "current"
        }
        guard let currentPath else {
            for path in discoveredLogs {
                guard let data = try source.data(forPath: path) else { continue }
                try budget.includeEncoded(data.count, limits: limits)
                guard data.isEmpty else {
                    throw FoundryImportError.unsupportedLevelDBLog(path)
                }
            }
            guard discoveredTables.count == 1 else {
                throw FoundryImportError.unsupportedLevelDBTableSet(
                    pack: packName,
                    tableCount: discoveredTables.count
                )
            }
            return FoundryLevelDBLiveFiles(tables: discoveredTables, logs: [])
        }
        guard let currentData = try source.data(forPath: currentPath),
              let currentText = String(data: currentData, encoding: .utf8) else {
            throw FoundryImportError.corruptLevelDB("The CURRENT file is not UTF-8.")
        }
        try budget.includeEncoded(currentData.count, limits: limits)
        let manifestName = currentText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard manifestName.hasPrefix("MANIFEST-"),
              !manifestName.contains("/"), !manifestName.contains("\\") else {
            throw FoundryImportError.corruptLevelDB("The CURRENT file names an invalid MANIFEST.")
        }
        let manifestPath = prefix + manifestName
        guard let manifestData = try source.data(forPath: manifestPath) else {
            throw FoundryImportError.corruptLevelDB("The CURRENT MANIFEST is missing.")
        }
        try budget.includeEncoded(manifestData.count, limits: limits)
        let state = try FoundryLevelDBManifestReader(limits: limits).state(in: manifestData)
        let tablesByNumber = try numberedLevelDBPaths(discoveredTables, kind: "SSTable")
        let missingNumbers = state.activeFileNumbers.subtracting(tablesByNumber.keys)
        guard missingNumbers.isEmpty else {
            throw FoundryImportError.corruptLevelDB("The MANIFEST references a missing SSTable.")
        }
        let tablePaths = state.activeFileNumbers.compactMap { tablesByNumber[$0] }.sorted()

        let logsByNumber = try numberedLevelDBPaths(discoveredLogs, kind: "write-ahead log")
        guard let minimumLogNumber = state.logNumber else {
            for path in discoveredLogs {
                guard let data = try source.data(forPath: path) else { continue }
                try budget.includeEncoded(data.count, limits: limits)
                guard data.isEmpty else {
                    throw FoundryImportError.corruptLevelDB(
                        "The MANIFEST does not identify which non-empty write-ahead logs are live."
                    )
                }
            }
            return FoundryLevelDBLiveFiles(tables: tablePaths, logs: [])
        }
        let previousLogNumber = state.previousLogNumber.flatMap { $0 == 0 ? nil : $0 }
        let requiredLogNumbers = Set([minimumLogNumber == 0 ? nil : minimumLogNumber, previousLogNumber].compactMap { $0 })
        guard requiredLogNumbers.isSubset(of: Set(logsByNumber.keys)) else {
            throw FoundryImportError.corruptLevelDB("The MANIFEST references a missing live write-ahead log.")
        }
        let logPaths = logsByNumber.compactMap { number, path in
            number >= minimumLogNumber || previousLogNumber == number ? path : nil
        }.sorted()
        return FoundryLevelDBLiveFiles(tables: tablePaths, logs: logPaths)
    }

    func numberedLevelDBPaths(_ paths: [String], kind: String) throws -> [UInt64: String] {
        var result: [UInt64: String] = [:]
        for path in paths {
            let stem = URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent
            guard let number = UInt64(stem), result[number] == nil else {
                throw FoundryImportError.corruptLevelDB("A \(kind) filename is invalid or duplicated.")
            }
            result[number] = path
        }
        return result
    }

    func decodeLegacyDatabase(
        _ spec: FoundryVTTCollectionSpec,
        packageKind: FoundryVTTPackageKind,
        packageID: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        guard let data = try source.data(forPath: spec.path) else { throw FoundryImportError.missingPack(spec.name) }
        try budget.includeEncoded(data.count, limits: limits)
        var current: [String: FoundryJSONValue] = [:]
        var diagnostics: [FoundryImportDiagnostic] = []
        var omittedDiagnosticCount = 0
        let diagnosticLimit = max(0, limits.maximumDiagnosticCount)
        for (lineNumber, line) in FoundryVTTLineSequence(data).enumerated() {
            try Task.checkCancellation()
            guard lineNumber < max(0, limits.maximumRecordCount) else {
                throw FoundryImportError.tooManyDocuments(lineNumber + 1)
            }
            let trimmed = line.foundryTrimmingASCIIWhitespace()
            guard !trimmed.isEmpty else { continue }
            try budget.includeDecoded(trimmed.count, limits: limits)
            do {
                let raw = try FoundryVTTRawJSON.decode(Data(trimmed), context: spec.path)
                guard let object = raw.objectValue else {
                    throw FoundryImportError.invalidDocument(pack: spec.name, key: "line \(lineNumber + 1)")
                }
                let id = object["_id"]?.stringValue
                    ?? object["id"]?.stringValue
                    ?? "line-\(lineNumber + 1)"
                if object["$$deleted"]?.boolValue == true {
                    current.removeValue(forKey: id)
                } else {
                    current[id] = raw
                }
            } catch {
                if diagnostics.count < diagnosticLimit {
                    diagnostics.append(FoundryImportDiagnostic(
                        severity: .warning,
                        code: "invalid-nedb-record",
                        message: "Skipped invalid JSON at line \(lineNumber + 1) of \(spec.name).",
                        packName: spec.name
                    ))
                } else {
                    omittedDiagnosticCount += 1
                }
            }
        }
        if omittedDiagnosticCount > 0, diagnosticLimit > 0 {
            if diagnostics.count == diagnosticLimit {
                diagnostics.removeLast()
                omittedDiagnosticCount += 1
            }
            diagnostics.append(FoundryImportDiagnostic(
                severity: .warning,
                code: "diagnostics-truncated",
                message: "Suppressed \(omittedDiagnosticCount) invalid records in \(spec.name).",
                packName: spec.name
            ))
        }
        let decoded = try FoundryVTTDocumentDecoder(
            packageKind: packageKind,
            packageID: packageID,
            spec: spec,
            limits: limits
        ).decodeRawDocuments(current.map { ($0.key, $0.value) }, budget: &budget)
        return (decoded.collection, diagnostics + decoded.diagnostics)
    }

    func decodeJSONCollection(
        _ spec: FoundryVTTCollectionSpec,
        packageKind: FoundryVTTPackageKind,
        packageID: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        guard let data = try source.data(forPath: spec.path) else { throw FoundryImportError.missingPack(spec.name) }
        try budget.includeEncoded(data.count, limits: limits)
        try budget.includeDecoded(data.count, limits: limits)
        let raw = try FoundryVTTRawJSON.decode(data, context: spec.path)
        let documents: [(String, FoundryJSONValue)]
        if let array = raw.arrayValue {
            documents = array.enumerated().map { index, value in
                (value["_id"]?.stringValue ?? value["id"]?.stringValue ?? "document-\(index + 1)", value)
            }
        } else if let object = raw.objectValue,
                  let array = object["documents"]?.arrayValue {
            documents = array.enumerated().map { index, value in
                (value["_id"]?.stringValue ?? value["id"]?.stringValue ?? "document-\(index + 1)", value)
            }
        } else {
            let id = raw["_id"]?.stringValue ?? raw["id"]?.stringValue ?? spec.name
            documents = [(id, raw)]
        }
        let collectionRawData: FoundryJSONValue? = raw.arrayValue != nil || raw["documents"]?.arrayValue != nil
            ? raw
            : spec.rawData
        let decodedSpec = FoundryVTTCollectionSpec(
            id: spec.id,
            name: spec.name,
            label: spec.label,
            path: spec.path,
            declaredType: spec.declaredType,
            rawData: collectionRawData
        )
        return try FoundryVTTDocumentDecoder(
            packageKind: packageKind,
            packageID: packageID,
            spec: decodedSpec,
            limits: limits
        ).decodeRawDocuments(documents, budget: &budget)
    }
}

struct FoundryLevelDBRecordMerger {
    static func currentRecords(_ records: [FoundryLevelDBRecord]) throws -> [FoundryLevelDBRecord] {
        var current: [String: FoundryLevelDBRecord] = [:]
        var recordsBySequence: [UInt64: FoundryLevelDBRecord] = [:]
        for record in records {
            if let existingSequence = recordsBySequence[record.sequence] {
                guard record == existingSequence else {
                    throw FoundryImportError.corruptLevelDB(
                        "The same LevelDB sequence number has conflicting records."
                    )
                }
            } else {
                recordsBySequence[record.sequence] = record
            }
            if let existing = current[record.key] {
                if record.sequence < existing.sequence { continue }
                if record.sequence == existing.sequence {
                    guard record.operation == existing.operation, record.value == existing.value else {
                        throw FoundryImportError.corruptLevelDB(
                            "The same key and sequence have conflicting LevelDB values."
                        )
                    }
                    continue
                }
            }
            current[record.key] = record
        }
        return current.values
            .filter { $0.operation == .value }
            .sorted { $0.key < $1.key }
    }
}

private struct FoundryVTTRecordComponent: Hashable {
    let collection: String
    let id: String
    let documentType: FoundryDocumentType
}

private struct FoundryVTTDocumentDecoder {
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
                let raw = try FoundryVTTRawJSON.decode(record.value, context: record.key)
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

private extension FoundryVTTDocumentDecoder {
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

    func decodeDocument(
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
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

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

private extension FoundryDocumentType {
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

private extension FoundryDocument {
    static func foundrySort(_ lhs: Self, _ rhs: Self) -> Bool {
        let leftSort = lhs.sort ?? 0
        let rightSort = rhs.sort ?? 0
        if leftSort != rightSort { return leftSort < rightSort }
        if lhs.name != rhs.name { return lhs.name < rhs.name }
        return lhs.id < rhs.id
    }
}

private enum FoundryVTTDataSource: Sendable {
    case archive(FoundryZIPArchive, sourceSHA256: String)
    case directory(root: URL, paths: [String], pathSet: Set<String>, limits: FoundryImportLimits, selectedPath: String?)

    init(url: URL, limits: FoundryImportLimits) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values.isDirectory == true {
            let root = url.standardizedFileURL.resolvingSymlinksInPath()
            let paths = try Self.directoryPaths(at: root, limits: limits)
            self = .directory(
                root: root,
                paths: paths,
                pathSet: Set(paths),
                limits: limits,
                selectedPath: nil
            )
            return
        }
        guard let fileSize = values.fileSize, fileSize <= limits.maximumArchiveSize else {
            throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
        }
        let lowercased = url.lastPathComponent.lowercased()
        if FoundryVTTPath.isManifest(lowercased) {
            throw FoundryImportError.bareManifestRequiresContainer(url.lastPathComponent)
        }
        let isPlainFile = lowercased.hasSuffix(".json")
            || lowercased.hasSuffix(".db")
            || lowercased.hasSuffix(".ldb")
            || lowercased.hasSuffix(".sst")
            || lowercased.hasSuffix(".mrpgfoundry")
        if isPlainFile {
            let root = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            let selected = try FoundryVTTPath.normalized(url.lastPathComponent)
            self = .directory(
                root: root,
                paths: [selected],
                pathSet: [selected],
                limits: limits,
                selectedPath: selected
            )
            return
        } else {
            try Task.checkCancellation()
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try Task.checkCancellation()
            self = .archive(
                try FoundryZIPArchive(data: data, limits: limits),
                sourceSHA256: foundrySHA256(data)
            )
        }
    }

    var paths: [String] {
        switch self {
        case .archive(let archive, _): archive.entryPaths
        case .directory(_, let paths, _, _, _): paths
        }
    }

    var selectedPath: String? {
        switch self {
        case .archive: nil
        case .directory(_, _, _, _, let path): path
        }
    }

    var sourceSHA256: String? {
        switch self {
        case .archive(_, let hash): return hash
        case .directory(_, _, _, _, let selectedPath):
            guard let selectedPath, let data = try? data(forPath: selectedPath) else { return nil }
            return foundrySHA256(data)
        }
    }

    func contains(path: String) -> Bool {
        switch self {
        case .archive(let archive, _): archive.contains(path: path)
        case .directory(_, _, let pathSet, _, _): pathSet.contains(path)
        }
    }

    func data(forPath path: String) throws -> Data? {
        switch self {
        case .archive(let archive, _):
            return try archive.data(forPath: path)
        case .directory(let root, _, let pathSet, let limits, let selectedPath):
            guard pathSet.contains(path) else { return nil }
            let candidate = root.appending(path: path).standardizedFileURL.resolvingSymlinksInPath()
            let rootPrefix = root.path.hasSuffix("/") ? root.path : root.path + "/"
            guard candidate.path.hasPrefix(rootPrefix) else {
                throw FoundryImportError.invalidArchive("A package path escapes its selected directory.")
            }
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { return nil }
            let maximumSize = selectedPath == path && path.lowercased().hasSuffix(".mrpgfoundry")
                ? limits.maximumArchiveSize
                : limits.maximumEntrySize
            guard let size = values.fileSize, size <= maximumSize else {
                throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
            }
            return try Data(contentsOf: candidate, options: .mappedIfSafe)
        }
    }
}

private extension FoundryVTTDataSource {
    static func directoryPaths(at root: URL, limits: FoundryImportLimits) throws -> [String] {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let rootPrefix = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw FoundryImportError.unsupportedSource }
        var result: [String] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let canonical = fileURL.standardizedFileURL.resolvingSymlinksInPath()
            guard canonical.path.hasPrefix(rootPrefix) else {
                throw FoundryImportError.invalidArchive("A package path escapes its selected directory.")
            }
            result.append(try FoundryVTTPath.normalized(String(canonical.path.dropFirst(rootPrefix.count))))
            guard result.count <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(result.count)
            }
        }
        return result.sorted()
    }
}

private enum FoundryVTTPath {
    static func normalized(_ path: String) throws -> String {
        let replacedPrefix = path.hasPrefix("./") ? String(path.dropFirst(2)) : path
        guard !replacedPrefix.isEmpty, !replacedPrefix.hasPrefix("/"), !replacedPrefix.hasPrefix("\\"),
              !replacedPrefix.contains("\\"), !replacedPrefix.contains("\0") else {
            throw FoundryImportError.invalidArchive("The package contains an unsafe path.")
        }
        var components: [Substring] = []
        for component in replacedPrefix.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": throw FoundryImportError.invalidArchive("The package contains a path traversal component.")
            default: components.append(component)
            }
        }
        guard !components.isEmpty else { throw FoundryImportError.invalidArchive("The package contains an empty path.") }
        return components.joined(separator: "/")
    }

    static func join(_ base: String, _ relative: String) throws -> String {
        let clean = relative.hasPrefix("./") ? String(relative.dropFirst(2)) : relative
        return try normalized(base + clean)
    }

    static func isManifest(_ path: String) -> Bool {
        guard let name = path.split(separator: "/").last?.lowercased() else { return false }
        return ["system.json", "module.json", "world.json"].contains(name)
    }

    static func isLicensePath(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return !lowercased.hasSuffix("/")
            && (lowercased.contains("license") || lowercased.contains("copying") || lowercased.contains("attribution"))
    }
}

private enum FoundryVTTRawJSON {
    static func decode(_ data: Data, context: String) throws -> FoundryJSONValue {
        let decoder = JSONDecoder()
        decoder.userInfo[.masterRPGFoundrySourceJSON] = true
        decoder.userInfo[.masterRPGFoundryJSONDepth] = FoundryJSONDepthCounter()
        do {
            return try decoder.decode(FoundryJSONValue.self, from: data)
        } catch {
            throw FoundryImportError.invalidArchive("\(context) is not valid JSON.")
        }
    }
}

private extension FoundryJSONValue {
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

private extension Data.SubSequence {
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

/// Iterates mapped or in-memory input without materializing an array containing every line.
private struct FoundryVTTLineSequence: Sequence, IteratorProtocol {
    private let data: Data
    private var nextStart: Data.Index?

    init(_ data: Data) {
        self.data = data
        nextStart = data.startIndex
    }

    mutating func next() -> Data.SubSequence? {
        guard let start = nextStart, start < data.endIndex else {
            nextStart = nil
            return nil
        }

        var end = start
        while end < data.endIndex, data[end] != 0x0a {
            data.formIndex(after: &end)
        }
        if end < data.endIndex {
            nextStart = data.index(after: end)
            return data[start..<end]
        }

        nextStart = nil
        return data[start..<data.endIndex]
    }
}

private enum FoundryVTTDocumentIdentityValidator {
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

private enum FoundryVTTStatisticsBuilder {
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

private enum FoundryVTTAssetCollector {
    static let pathExtensions = Set([
        "aac", "aif", "aiff", "apng", "avif", "bmp", "caf", "flac", "gif", "glb", "gltf",
        "heic", "heif", "jpeg", "jpg", "m4a", "m4v", "mp3", "mp4", "oga", "ogg", "ogv",
        "opus", "pdf", "png", "svg", "tif", "tiff", "usdz", "wav", "webm", "webp",
    ])

    static func paths(in collections: [FoundryDocumentCollection]) -> Set<String> {
        var result = Set<String>()
        for collection in collections {
            for document in collection.documents { collect(document.rawData, into: &result) }
        }
        return result
    }

    static func collect(_ value: FoundryJSONValue, into result: inout Set<String>) {
        switch value {
        case .object(let object):
            for child in object.values { collect(child, into: &result) }
        case .array(let values):
            for child in values { collect(child, into: &result) }
        case .string(let string):
            for reference in [string] + htmlAttributeReferences(in: string) {
                let encodedPath = reference
                    .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
                    .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
                let path = String(encodedPath).removingPercentEncoding ?? String(encodedPath)
                if pathExtensions.contains(URL(filePath: path).pathExtension.lowercased()) {
                    result.insert(reference)
                }
            }
        default:
            break
        }
    }

    /// Extracts only `src` and `href` attribute values from tag text. This deliberately does not
    /// instantiate an HTML parser, render content, execute scripts, or resolve any URL.
    static func htmlAttributeReferences(in html: String) -> [String] {
        let bytes = Array(html.utf8)
        var references: [String] = []
        var index = bytes.startIndex
        var isInsideTag = false

        while index < bytes.endIndex {
            if !isInsideTag {
                isInsideTag = bytes[index] == 0x3c // <
                index += 1
                continue
            }
            if bytes[index] == 0x3e { // >
                isInsideTag = false
                index += 1
                continue
            }
            if isHTMLWhitespace(bytes[index]) || bytes[index] == 0x2f { // /
                index += 1
                continue
            }

            let nameStart = index
            while index < bytes.endIndex, isHTMLAttributeNameByte(bytes[index]) {
                index += 1
            }
            guard nameStart < index else {
                index += 1
                continue
            }
            let isReferenceAttribute = isReferenceAttribute(bytes[nameStart..<index])
            while index < bytes.endIndex, isHTMLWhitespace(bytes[index]) { index += 1 }
            guard index < bytes.endIndex, bytes[index] == 0x3d else { continue } // =
            index += 1
            while index < bytes.endIndex, isHTMLWhitespace(bytes[index]) { index += 1 }
            guard index < bytes.endIndex else { break }

            let quote: UInt8? = switch bytes[index] {
            case 0x22, 0x27: bytes[index] // " or '
            default: nil
            }
            if quote != nil { index += 1 }
            let valueStart = index
            if let quote {
                while index < bytes.endIndex, bytes[index] != quote { index += 1 }
            } else {
                while index < bytes.endIndex,
                      !isHTMLWhitespace(bytes[index]),
                      bytes[index] != 0x3e { // >
                    index += 1
                }
            }
            if isReferenceAttribute, valueStart < index {
                references.append(String(decoding: bytes[valueStart..<index], as: UTF8.self))
            }
            if quote != nil, index < bytes.endIndex { index += 1 }
        }
        return references
    }

    static func isReferenceAttribute(_ name: ArraySlice<UInt8>) -> Bool {
        let lowercased = name.map { byte in
            (0x41...0x5a).contains(byte) ? byte + 0x20 : byte
        }
        return lowercased == Array("src".utf8) || lowercased == Array("href".utf8)
    }

    static func isHTMLWhitespace(_ byte: UInt8) -> Bool {
        byte == 0x09 || byte == 0x0a || byte == 0x0c || byte == 0x0d || byte == 0x20
    }

    static func isHTMLAttributeNameByte(_ byte: UInt8) -> Bool {
        !isHTMLWhitespace(byte) && ![0x22, 0x27, 0x2f, 0x3c, 0x3d, 0x3e].contains(byte)
    }
}

private enum FoundryVTTResourceResolver {
    static func resolve(
        assetPaths: [String],
        kind: FoundryVTTPackageKind,
        packageID: String,
        basePath: String,
        source: FoundryVTTDataSource,
        limits: FoundryImportLimits
    ) throws -> [FoundryPackageResource] {
        var packagedBytes = 0
        return try assetPaths.map { logicalPath in
            if isRemote(logicalPath) {
                return FoundryPackageResource(
                    logicalPath: logicalPath,
                    packagePath: nil,
                    location: .remote,
                    byteCount: nil,
                    sha256: nil
                )
            }
            for candidate in candidates(
                for: logicalPath,
                kind: kind,
                packageID: packageID,
                basePath: basePath
            ) where source.contains(path: candidate) {
                guard let data = try source.data(forPath: candidate) else { continue }
                let (next, overflow) = packagedBytes.addingReportingOverflow(data.count)
                guard !overflow, next <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : next)
                }
                packagedBytes = next
                return FoundryPackageResource(
                    logicalPath: logicalPath,
                    packagePath: candidate,
                    location: .packaged,
                    byteCount: data.count,
                    sha256: foundrySHA256(data)
                )
            }
            return FoundryPackageResource(
                logicalPath: logicalPath,
                packagePath: nil,
                location: isInstallationPath(logicalPath) ? .foundryInstallation : .unresolved,
                byteCount: nil,
                sha256: nil
            )
        }
    }

    static func candidates(
        for logicalPath: String,
        kind: FoundryVTTPackageKind,
        packageID: String,
        basePath: String
    ) -> [String] {
        let encodedPath = String(logicalPath
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        // Decode once, then apply package-path validation. Encoded separators and `..` therefore
        // become visible to the traversal checks instead of being passed to filesystem lookup.
        guard let clean = encodedPath.removingPercentEncoding else { return [] }
        let packageDirectory: String? = switch kind {
        case .system: "systems"
        case .module: "modules"
        case .world: "worlds"
        case .exportedDocument, .documentCollection: nil
        }
        var result: [String] = []
        if let packageDirectory {
            let prefix = "\(packageDirectory)/\(packageID)/"
            if clean.hasPrefix(prefix),
               let mapped = try? FoundryVTTPath.join(basePath, String(clean.dropFirst(prefix.count))) {
                result.append(mapped)
            }
        }
        if let normalized = try? FoundryVTTPath.normalized(clean) { result.append(normalized) }
        if !basePath.isEmpty, let mapped = try? FoundryVTTPath.join(basePath, clean) { result.append(mapped) }
        var seen = Set<String>()
        return result.filter { seen.insert($0).inserted }
    }

    static func isRemote(_ path: String) -> Bool {
        let value = path.lowercased()
        return value.hasPrefix("http://") || value.hasPrefix("https://") || value.hasPrefix("data:")
    }

    static func isInstallationPath(_ path: String) -> Bool {
        ["icons/", "modules/", "systems/", "ui/", "worlds/"].contains { path.hasPrefix($0) }
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
        let path = sourceURL.standardizedFileURL.path
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

private struct FoundryBridgeDecoder {
    let limits: FoundryImportLimits

    func decodePackage(source: FoundryVTTDataSource) throws -> FoundryVTTImportPackage {
        guard let selectedPath = source.selectedPath,
              let data = try source.data(forPath: selectedPath) else {
            throw FoundryImportError.unsupportedSource
        }
        let contents = try decodeContents(data, retainingAssetPaths: [])
        let header = contents.header
        guard let sourceObject = header["source"]?.objectValue else {
            throw FoundryImportError.invalidManifest("The bridge source declaration is missing.")
        }
        let sourceKind = sourceObject["kind"]?.stringValue ?? "selection"
        let kind: FoundryVTTPackageKind = switch sourceKind {
        case "world": .world
        case "adventure": .documentCollection
        default: .exportedDocument
        }
        let packageID = sourceObject["id"]?.stringValue ?? "foundry-export"
        let title = sourceObject["title"]?.stringValue ?? packageID
        let manifest = FoundryVTTPackageManifest(
            kind: kind,
            id: packageID,
            title: title,
            descriptionHTML: nil,
            version: sourceObject["systemVersion"]?.foundryScalarString,
            systemID: sourceObject["systemID"]?.stringValue,
            compatibility: FoundryCompatibility(
                minimum: nil,
                verified: header["foundryVersion"]?.foundryScalarString,
                maximum: nil
            ),
            rawData: .object(header)
        )

        var grouped: [FoundryBridgeGroupKey: [FoundryBridgeDocumentRecord]] = [:]
        for record in contents.documents {
            grouped[FoundryBridgeGroupKey(collection: record.collection, documentType: record.documentType), default: []]
                .append(record)
        }
        var budget = FoundryVTTReadBudget(encodedBytes: data.count, decodedBytes: data.count, recordCount: 0)
        guard data.count <= limits.maximumRuleDataSize else { throw FoundryImportError.fileTooLarge(data.count) }
        var collections: [FoundryDocumentCollection] = []
        var diagnostics = contents.diagnostics
        for groupKey in grouped.keys.sorted(by: {
            $0.collection == $1.collection
                ? $0.documentType.rawValue < $1.documentType.rawValue
                : $0.collection < $1.collection
        }) {
            guard let records = grouped[groupKey] else { continue }
            let declared = groupKey.documentType != .unknown
                ? groupKey.documentType
                : .inferred(fromCollectionName: groupKey.collection)
            let spec = FoundryVTTCollectionSpec(
                id: "bridge:\(groupKey.collection):\(declared.rawValue)",
                name: groupKey.collection,
                label: groupKey.collection,
                path: selectedPath,
                declaredType: declared,
                rawData: nil
            )
            let rawDocuments = records.enumerated().map { index, record in
                let fallback = record.data["_id"]?.stringValue
                    ?? record.uuid.split(separator: ".").last.map(String.init)
                    ?? "document-\(index + 1)"
                return (fallback, record.data)
            }
            let result = try FoundryVTTDocumentDecoder(
                packageKind: kind,
                packageID: packageID,
                spec: spec,
                limits: limits
            ).decodeRawDocuments(rawDocuments, budget: &budget)
            let recordsByID = Dictionary(records.map { record in
                let id = record.data["_id"]?.stringValue
                    ?? record.uuid.split(separator: ".").last.map(String.init)
                    ?? record.uuid
                return (id, record)
            }, uniquingKeysWith: { first, _ in first })
            let documents = result.collection.documents.map { document in
                guard let record = recordsByID[document.documentID] else { return document }
                return document.withBridgeSource(uuid: record.uuid, parentUUID: record.parentUUID)
            }
            collections.append(FoundryDocumentCollection(
                id: result.collection.id,
                name: result.collection.name,
                label: result.collection.label,
                sourcePath: result.collection.sourcePath,
                declaredDocumentType: result.collection.declaredDocumentType,
                documents: documents,
                folders: result.collection.folders,
                rawData: result.collection.rawData
            ))
            diagnostics.append(contentsOf: result.diagnostics)
        }

        var resources = contents.assetMetadata.map { path, metadata in
            FoundryPackageResource(
                logicalPath: path,
                packagePath: "bridge-assets/\(path)",
                location: .packaged,
                byteCount: metadata.byteCount,
                sha256: metadata.sha256
            )
        }
        for reference in contents.assetReferences where !contents.assetMetadata.keys.contains(reference.path) {
            let location: FoundryPackageResource.Location = switch reference.status {
            case "remote": .remote
            case "core", "external": .foundryInstallation
            default: .unresolved
            }
            resources.append(FoundryPackageResource(
                logicalPath: reference.path,
                packagePath: nil,
                location: location,
                byteCount: nil,
                sha256: nil
            ))
        }
        var representedPaths = Set(resources.map(\.logicalPath))
        let referencedPaths = FoundryVTTAssetCollector.paths(in: collections)
        for path in referencedPaths.sorted() where representedPaths.insert(path).inserted {
            resources.append(FoundryPackageResource(
                logicalPath: path,
                packagePath: nil,
                location: FoundryVTTResourceResolver.isRemote(path) ? .remote : .unresolved,
                byteCount: nil,
                sha256: nil
            ))
        }
        resources.sort { $0.logicalPath < $1.logicalPath }

        try FoundryVTTDocumentIdentityValidator.validate(collections)
        let statistics = FoundryVTTStatisticsBuilder.build(collections)
        diagnostics.append(FoundryImportDiagnostic(
            severity: .information,
            code: "bridge-decoded",
            message: "Decoded MasterRPG Foundry bridge version 1 without evaluating scripts or HTML."
        ))
        return FoundryVTTImportPackage(
            sourceSHA256: source.sourceSHA256,
            kind: kind,
            manifestPath: nil,
            manifest: manifest,
            collections: collections,
            resources: resources,
            diagnostics: diagnostics,
            statistics: statistics
        )
    }

    func resourceData(logicalPaths: Set<String>, sourceURL: URL) throws -> [String: Data] {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= limits.maximumArchiveSize else {
            throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
        }
        try Task.checkCancellation()
        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        try Task.checkCancellation()
        let contents = try decodeContents(data, retainingAssetPaths: logicalPaths)
        guard Set(contents.assets.keys) == logicalPaths else {
            let missing = logicalPaths.subtracting(contents.assets.keys).sorted().first ?? "asset"
            throw FoundryImportError.resourceUnavailable(missing)
        }
        return contents.assets
    }

    func allResourceData(sourceURL: URL) throws -> [String: Data] {
        let values = try sourceURL.resourceValues(forKeys: [.fileSizeKey])
        guard let size = values.fileSize, size <= limits.maximumArchiveSize else {
            throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
        }
        try Task.checkCancellation()
        let data = try Data(contentsOf: sourceURL, options: .mappedIfSafe)
        try Task.checkCancellation()
        return try decodeContents(data, retainingAssetPaths: nil).assets
    }
}

private extension FoundryBridgeDecoder {
    struct Contents {
        let header: [String: FoundryJSONValue]
        let documents: [FoundryBridgeDocumentRecord]
        let assetMetadata: [String: FoundryBridgeAssetMetadata]
        let assets: [String: Data]
        let assetReferences: [FoundryBridgeAssetReference]
        let diagnostics: [FoundryImportDiagnostic]
    }

    func decodeContents(
        _ data: Data,
        retainingAssetPaths: Set<String>? = nil
    ) throws -> Contents {
        guard data.count <= limits.maximumArchiveSize else { throw FoundryImportError.fileTooLarge(data.count) }
        var header: [String: FoundryJSONValue]?
        var documents: [FoundryBridgeDocumentRecord] = []
        var assetMetadata: [String: FoundryBridgeAssetMetadata] = [:]
        var assets: [String: Data] = [:]
        var references: [FoundryBridgeAssetReference] = []
        var diagnostics: [FoundryImportDiagnostic] = []
        var omittedDiagnosticCount = 0
        let diagnosticLimit = max(0, limits.maximumDiagnosticCount)
        var endCounts: (documentCount: Int, assetCount: Int)?
        var decodedAssetBytes = 0
        let bridgeLineByteLimit = maximumBridgeLineByteCount()
        for (lineIndex, line) in FoundryVTTLineSequence(data).enumerated() {
            try Task.checkCancellation()
            guard lineIndex < max(0, limits.maximumRecordCount) else {
                throw FoundryImportError.tooManyDocuments(lineIndex + 1)
            }
            let trimmed = line.foundryTrimmingASCIIWhitespace()
            guard !trimmed.isEmpty else { continue }
            guard trimmed.count <= bridgeLineByteLimit else {
                throw FoundryImportError.fileTooLarge(trimmed.count)
            }
            let raw = try FoundryVTTRawJSON.decode(Data(trimmed), context: "bridge line \(lineIndex + 1)")
            guard let object = raw.objectValue, let record = object["record"]?.stringValue else {
                throw FoundryImportError.invalidArchive("Bridge line \(lineIndex + 1) has no record kind.")
            }
            guard record == "asset" || trimmed.count <= limits.maximumEntrySize else {
                throw FoundryImportError.fileTooLarge(trimmed.count)
            }
            if header == nil, record != "manifest" {
                throw FoundryImportError.invalidManifest("The first bridge record is not the manifest.")
            }
            if endCounts != nil {
                throw FoundryImportError.invalidArchive("The bridge end record is not last.")
            }
            switch record {
            case "manifest":
                guard header == nil,
                      object["format"]?.stringValue == "masterrpg-foundry-bridge",
                      object["version"]?.integerValue == 1 else {
                    throw FoundryImportError.invalidManifest("The bridge format or version is unsupported.")
                }
                _ = try declaredCounts(
                    in: object,
                    context: "bridge manifest",
                    invalid: FoundryImportError.invalidManifest
                )
                header = object
            case "document":
                guard let collection = object["collection"]?.stringValue,
                      let uuid = object["uuid"]?.stringValue,
                      let documentData = object["data"], documentData.objectValue != nil else {
                    throw FoundryImportError.invalidArchive("Bridge document at line \(lineIndex + 1) is incomplete.")
                }
                documents.append(FoundryBridgeDocumentRecord(
                    collection: collection,
                    documentType: .inferred(from: object["documentType"]?.stringValue),
                    uuid: uuid,
                    parentUUID: object["parentUUID"]?.stringValue,
                    data: documentData
                ))
                guard documents.count <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(documents.count)
                }
            case "asset":
                guard let rawPath = object["path"]?.stringValue,
                      let encoded = object["data"]?.stringValue,
                      let mediaType = object["mediaType"]?.stringValue,
                      mediaType.utf8.count <= 256,
                      object["encoding"]?.stringValue == "base64",
                      let expectedSHA = object["sha256"]?.stringValue else {
                    throw FoundryImportError.invalidArchive("Bridge asset at line \(lineIndex + 1) is incomplete.")
                }
                guard rawPath.utf8.count <= 4_096 else {
                    throw FoundryImportError.invalidArchive("A bridge asset path is too long.")
                }
                let path = try FoundryVTTPath.normalized(rawPath)
                guard assetMetadata[path] == nil else {
                    throw FoundryImportError.invalidArchive("The bridge contains duplicate asset path \(path).")
                }
                guard expectedSHA.count == 64,
                      expectedSHA.allSatisfy({ $0.isHexDigit && !$0.isUppercase }) else {
                    throw FoundryImportError.resourceIntegrityFailure(path)
                }
                guard decodedAssetBytes <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(decodedAssetBytes)
                }
                let remainingBatchBytes = limits.maximumResourceBatchSize - decodedAssetBytes
                let decoded = try FoundryBoundedBase64.decode(
                    encoded,
                    maximumDecodedByteCount: min(limits.maximumEntrySize, remainingBatchBytes),
                    invalidMessage: "Bridge asset at line \(lineIndex + 1) is not valid base64."
                )
                let (nextAssetBytes, overflow) = decodedAssetBytes.addingReportingOverflow(decoded.count)
                guard !overflow, nextAssetBytes <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextAssetBytes)
                }
                decodedAssetBytes = nextAssetBytes
                guard foundrySHA256(decoded) == expectedSHA else {
                    throw FoundryImportError.resourceIntegrityFailure(path)
                }
                assetMetadata[path] = FoundryBridgeAssetMetadata(
                    byteCount: decoded.count,
                    sha256: expectedSHA
                )
                guard assetMetadata.count <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(assetMetadata.count)
                }
                if retainingAssetPaths == nil || retainingAssetPaths?.contains(path) == true {
                    assets[path] = decoded
                }
            case "assetReference":
                guard let rawPath = object["path"]?.stringValue,
                      let status = object["status"]?.stringValue else {
                    throw FoundryImportError.invalidArchive("Bridge asset reference at line \(lineIndex + 1) is incomplete.")
                }
                references.append(FoundryBridgeAssetReference(
                    path: try normalizeReferencePath(rawPath, status: status),
                    status: status
                ))
                guard references.count <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(references.count)
                }
            case "end":
                guard endCounts == nil else {
                    throw FoundryImportError.invalidArchive("The bridge contains two end records.")
                }
                endCounts = try declaredCounts(
                    in: object,
                    context: "bridge end record",
                    invalid: FoundryImportError.invalidArchive
                )
            default:
                if diagnostics.count < diagnosticLimit {
                    diagnostics.append(FoundryImportDiagnostic(
                        severity: .warning,
                        code: "unknown-bridge-record",
                        message: "Skipped unknown bridge record \(record) at line \(lineIndex + 1)."
                    ))
                } else {
                    omittedDiagnosticCount += 1
                }
            }
        }
        if omittedDiagnosticCount > 0, diagnosticLimit > 0 {
            if diagnostics.count == diagnosticLimit {
                diagnostics.removeLast()
                omittedDiagnosticCount += 1
            }
            diagnostics.append(FoundryImportDiagnostic(
                severity: .warning,
                code: "diagnostics-truncated",
                message: "Suppressed \(omittedDiagnosticCount) bridge diagnostics."
            ))
        }
        guard let header else { throw FoundryImportError.invalidManifest("The bridge manifest is missing.") }
        let manifestCounts = try declaredCounts(
            in: header,
            context: "bridge manifest",
            invalid: FoundryImportError.invalidManifest
        )
        guard let endCounts else {
            throw FoundryImportError.invalidArchive("The bridge end record is missing; the export may be truncated.")
        }
        guard manifestCounts.documentCount == endCounts.documentCount,
              manifestCounts.assetCount == endCounts.assetCount else {
            throw FoundryImportError.invalidArchive("The bridge manifest and end record counts do not match.")
        }
        guard manifestCounts.documentCount == documents.count else {
            throw FoundryImportError.invalidArchive(
                "The bridge declares \(manifestCounts.documentCount) documents but contains \(documents.count)."
            )
        }
        guard manifestCounts.assetCount == assetMetadata.count else {
            throw FoundryImportError.invalidArchive(
                "The bridge declares \(manifestCounts.assetCount) included assets but contains \(assetMetadata.count)."
            )
        }
        let duplicateReferences = Dictionary(grouping: references, by: \.path).filter { $0.value.count > 1 }
        guard duplicateReferences.isEmpty,
              Set(references.map(\.path)).isDisjoint(with: assetMetadata.keys) else {
            throw FoundryImportError.invalidArchive("The bridge contains duplicate normalized asset paths.")
        }
        return Contents(
            header: header,
            documents: documents,
            assetMetadata: assetMetadata,
            assets: assets,
            assetReferences: references,
            diagnostics: diagnostics
        )
    }

    func declaredCounts(
        in object: [String: FoundryJSONValue],
        context: String,
        invalid: (String) -> FoundryImportError
    ) throws -> (documentCount: Int, assetCount: Int) {
        guard let rawDocumentCount = object["documentCount"]?.integerValue,
              rawDocumentCount >= 0,
              let documentCount = Int(exactly: rawDocumentCount),
              let rawAssetCount = object["assetCount"]?.integerValue,
              rawAssetCount >= 0,
              let assetCount = Int(exactly: rawAssetCount) else {
            throw invalid("The \(context) must declare nonnegative integer documentCount and assetCount values.")
        }
        let maximumCount = max(documentCount, assetCount)
        guard maximumCount <= limits.maximumDocumentCount else {
            throw FoundryImportError.tooManyDocuments(maximumCount)
        }
        return (documentCount, assetCount)
    }

    /// Asset records carry Base64, so their encoded JSON line is necessarily larger than the
    /// decoded `maximumEntrySize`. Bound it to canonical Base64 expansion plus small metadata,
    /// and still apply the decoded limit before allocating bytes.
    func maximumBridgeLineByteCount() -> Int {
        let archiveLimit = max(0, limits.maximumArchiveSize)
        let decodedLimit = max(0, limits.maximumEntrySize)
        let (roundedDecodedLimit, roundingOverflow) = decodedLimit.addingReportingOverflow(2)
        guard !roundingOverflow else { return archiveLimit }
        let groups = roundedDecodedLimit / 3
        let (encodedLimit, encodingOverflow) = groups.multipliedReportingOverflow(by: 4)
        guard !encodingOverflow else { return archiveLimit }
        let (lineLimit, metadataOverflow) = encodedLimit.addingReportingOverflow(65_536)
        return min(archiveLimit, metadataOverflow ? Int.max : lineLimit)
    }

    func normalizeReferencePath(_ path: String, status: String) throws -> String {
        if status == "remote" {
            guard let components = URLComponents(string: path),
                  ["http", "https"].contains(components.scheme?.lowercased() ?? ""),
                  components.host != nil else {
                throw FoundryImportError.invalidArchive("A remote bridge asset reference has an invalid URL.")
            }
            return path
        }
        return try FoundryVTTPath.normalized(path)
    }
}

private struct FoundryBridgeDocumentRecord {
    let collection: String
    let documentType: FoundryDocumentType
    let uuid: String
    let parentUUID: String?
    let data: FoundryJSONValue
}

private struct FoundryBridgeGroupKey: Hashable {
    let collection: String
    let documentType: FoundryDocumentType
}

private struct FoundryBridgeAssetReference {
    let path: String
    let status: String
}

private struct FoundryBridgeAssetMetadata {
    let byteCount: Int
    let sha256: String
}

private extension FoundryDocument {
    func withBridgeSource(uuid: String, parentUUID: String?) -> Self {
        Self(
            id: id,
            documentID: documentID,
            documentType: documentType,
            subtype: subtype,
            name: name,
            folderID: folderID,
            sort: sort,
            imagePath: imagePath,
            descriptionHTML: descriptionHTML,
            parentID: parentID,
            sourceUUID: uuid,
            sourceParentUUID: parentUUID,
            embeddedDocuments: embeddedDocuments,
            references: references,
            unknownFieldNames: unknownFieldNames,
            rawData: rawData
        )
    }
}
