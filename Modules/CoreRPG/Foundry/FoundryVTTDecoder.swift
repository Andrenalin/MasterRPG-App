// @copyright André Trettin

import CryptoKit
import Foundation

// The decode orchestration and discovery, split out of FoundryVTTImportReader.swift. See CODE_AUDIT_29 §9.9.

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
        let packageId = manifest?.id ?? "unmanifested-source"

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
                    packageId: packageId,
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
            packageId: packageId,
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
            systemId: object["system"]?.stringValue,
            compatibility: FoundryCompatibility(
                minimum: compatibility["minimum"]?.foundryScalarString,
                verified: compatibility["verified"]?.foundryScalarString,
                maximum: compatibility["maximum"]?.foundryScalarString
            ),
            rawData: raw
        )
    }
}

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
        packageId: String,
        source: FoundryVTTDataSource,
        budget: inout FoundryVTTReadBudget
    ) throws -> (collection: FoundryDocumentCollection, diagnostics: [FoundryImportDiagnostic]) {
        let lowercased = spec.path.lowercased()
        if lowercased.hasSuffix(".db") {
            return try decodeLegacyDatabase(
                spec,
                packageKind: packageKind,
                packageId: packageId,
                source: source,
                budget: &budget
            )
        }
        if lowercased.hasSuffix(".json") {
            return try decodeJSONCollection(
                spec,
                packageKind: packageKind,
                packageId: packageId,
                source: source,
                budget: &budget
            )
        }
        return try decodeLevelDBCollection(
            spec,
            packageKind: packageKind,
            packageId: packageId,
            source: source,
            budget: &budget
        )
    }
}

struct FoundryVTTRecordComponent: Hashable {
    let collection: String
    let id: String
    let documentType: FoundryDocumentType
}
