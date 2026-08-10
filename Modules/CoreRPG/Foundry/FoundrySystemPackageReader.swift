// @copyright André Trettin

import CryptoKit
import Foundation

/// Reads a Foundry VTT game-system package into a stable interchange model for supported rules.
///
/// The result is deliberately independent of Core Data and the app's current RPG modules. A
/// `RuleRPG` can map or persist it without learning ZIP or LevelDB internals.
public struct FoundrySystemPackageReader: Sendable {
    public let limits: FoundryImportLimits

    public init(limits: FoundryImportLimits = .default) {
        self.limits = limits
    }

    public func read(from url: URL) async throws -> FoundryRulePackage {
        let limits = limits
        let task = Task.detached(priority: .userInitiated) {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try Task.checkCancellation()
            return try Self.readSynchronously(from: url, limits: limits)
        }
        return try await withTaskCancellationHandler {
            let package = try await task.value
            try Task.checkCancellation()
            return package
        } onCancel: {
            task.cancel()
        }
    }

    /// Reopens resources issued by `read(from:)` while reusing the importer's path, CRC, size,
    /// provenance, and per-resource integrity checks.
    public func readResources(
        _ resources: [FoundryPackageResource],
        from url: URL,
        in package: FoundryRulePackage
    ) async throws -> [FoundryPackageResourceData] {
        guard Set(resources).count == resources.count else {
            throw FoundryImportError.duplicateResourceRequest
        }
        let limits = limits
        let task = Task.detached(priority: .userInitiated) {
            let hasSecurityScope = url.startAccessingSecurityScopedResource()
            defer {
                if hasSecurityScope {
                    url.stopAccessingSecurityScopedResource()
                }
            }
            try Task.checkCancellation()
            let source = try FoundryPackageDataSource(url: url, limits: limits)
            if let expectedSourceSHA256 = package.sourceSHA256,
               source.sourceSHA256 != expectedSourceSHA256 {
                throw FoundryImportError.sourceMismatch
            }
            let manifestPath = try source.manifestPath()
            guard manifestPath == package.manifestPath,
                  let manifestData = try source.data(forPath: manifestPath),
                  try FoundryManifestDecoder().decode(manifestData) == package.manifest else {
                throw FoundryImportError.sourceMismatch
            }

            let issuedResources = Set(package.resources)
            var result: [FoundryPackageResourceData] = []
            result.reserveCapacity(resources.count)
            var totalResourceBytes = 0
            for resource in resources {
                try Task.checkCancellation()
                guard issuedResources.contains(resource),
                      resource.location == .packaged,
                      let packagePath = resource.packagePath,
                      let byteCount = resource.byteCount,
                      let sha256 = resource.sha256,
                      let data = try source.data(forPath: packagePath) else {
                    throw FoundryImportError.resourceUnavailable(resource.logicalPath)
                }
                guard data.count == byteCount,
                      foundrySHA256(data) == sha256 else {
                    throw FoundryImportError.resourceIntegrityFailure(resource.logicalPath)
                }
                let (nextResourceBytes, overflow) = totalResourceBytes.addingReportingOverflow(data.count)
                guard !overflow, nextResourceBytes <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextResourceBytes)
                }
                totalResourceBytes = nextResourceBytes
                result.append(FoundryPackageResourceData(resource: resource, data: data))
            }
            return result
        }
        return try await withTaskCancellationHandler {
            let resources = try await task.value
            try Task.checkCancellation()
            return resources
        } onCancel: {
            task.cancel()
        }
    }

    public func readResource(
        _ resource: FoundryPackageResource,
        from url: URL,
        in package: FoundryRulePackage
    ) async throws -> Data {
        guard let data = try await readResources([resource], from: url, in: package).first?.data else {
            throw FoundryImportError.resourceUnavailable(resource.logicalPath)
        }
        return data
    }
}

private extension FoundrySystemPackageReader {
    static func readSynchronously(from url: URL, limits: FoundryImportLimits) throws -> FoundryRulePackage {
        let source = try FoundryPackageDataSource(url: url, limits: limits)
        let manifestPath = try source.manifestPath()
        guard let manifestData = try source.data(forPath: manifestPath) else {
            throw FoundryImportError.missingManifest
        }
        let manifest = try FoundryManifestDecoder().decode(manifestData)
        let basePath = String(manifestPath.dropLast("system.json".count))

        let proposedTemplatePath = try FoundryPackagePath.join(basePath, "template.json")
        let templatePath = source.contains(path: proposedTemplatePath) ? proposedTemplatePath : nil
        let templateData = try templatePath.flatMap { try source.data(forPath: $0) }
        let decodedTemplate = try templateData.map { try FoundryJSONDecoder.decode($0, context: "template.json") }
        let schemas = try decodedTemplate.map(FoundryTemplateDecoder().decode) ?? []

        var diagnostics: [FoundryImportDiagnostic] = []
        var compendiums: [FoundryCompendium] = []
        var totalEncodedTableBytes = 0
        var totalDecodedRecordBytes = 0
        var totalLevelDBRecords = 0
        var totalDocuments = 0

        for pack in manifest.packs {
            try Task.checkCancellation()
            let packPath = try FoundryPackagePath.join(basePath, pack.path)
            let packPrefix = packPath.hasSuffix("/") ? packPath : packPath + "/"
            let tablePaths = source.paths
                .filter { $0.hasPrefix(packPrefix) && $0.lowercased().hasSuffix(".ldb") }
                .sorted()
            guard !tablePaths.isEmpty else {
                throw FoundryImportError.missingPack(pack.name)
            }
            guard tablePaths.count == 1 else {
                throw FoundryImportError.unsupportedLevelDBTableSet(pack: pack.name, tableCount: tablePaths.count)
            }

            let logPaths = source.paths
                .filter { path in
                    guard path.hasPrefix(packPrefix), path.lowercased().hasSuffix(".log") else { return false }
                    return URL(fileURLWithPath: path).deletingPathExtension().lastPathComponent.allSatisfy(\.isNumber)
                }
                .sorted()
            for logPath in logPaths {
                guard let logData = try source.data(forPath: logPath) else { continue }
                guard logData.isEmpty else {
                    throw FoundryImportError.unsupportedLevelDBLog(logPath)
                }
            }

            var records: [FoundryLevelDBRecord] = []
            for tablePath in tablePaths {
                guard let data = try source.data(forPath: tablePath) else { continue }
                let (nextSize, overflow) = totalEncodedTableBytes.addingReportingOverflow(data.count)
                guard !overflow, nextSize <= limits.maximumRuleDataSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextSize)
                }
                totalEncodedTableBytes = nextSize

                let tableRecords = try FoundryLevelDBTableReader(limits: limits).records(in: data)
                let (nextRecordCount, recordCountOverflow) = totalLevelDBRecords.addingReportingOverflow(tableRecords.count)
                guard !recordCountOverflow, nextRecordCount <= limits.maximumDocumentCount else {
                    throw FoundryImportError.tooManyDocuments(recordCountOverflow ? Int.max : nextRecordCount)
                }
                totalLevelDBRecords = nextRecordCount
                for record in tableRecords {
                    let recordSize = record.key.utf8.count + record.value.count + MemoryLayout<UInt64>.size + 1
                    let (nextDecodedSize, decodedOverflow) = totalDecodedRecordBytes.addingReportingOverflow(recordSize)
                    guard !decodedOverflow, nextDecodedSize <= limits.maximumRuleDataSize else {
                        throw FoundryImportError.fileTooLarge(decodedOverflow ? Int.max : nextDecodedSize)
                    }
                    totalDecodedRecordBytes = nextDecodedSize
                }
                records.append(contentsOf: tableRecords)
            }

            let result = try FoundryCompendiumDecoder(
                systemID: manifest.id,
                pack: pack,
                maximumDocumentCount: limits.maximumDocumentCount
            ).decode(records)
            compendiums.append(result.compendium)
            diagnostics.append(contentsOf: result.diagnostics)
            totalDocuments += result.compendium.rules.count
            guard totalDocuments <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(totalDocuments)
            }
        }

        if manifest.id != "ds4" {
            diagnostics.append(FoundryImportDiagnostic(
                severity: .information,
                code: "generic-system-interpretation",
                message: "Supported Actor and Item payloads are preserved, but only generic subtype categories are available for system \(manifest.id)."
            ))
        }

        let contentVersions = Set(compendiums.flatMap(\.rules).compactMap {
            $0.rawData.value(at: "_stats.systemVersion")?.stringValue
        })
        for contentVersion in contentVersions.sorted() where contentVersion != manifest.version {
            diagnostics.append(FoundryImportDiagnostic(
                severity: .information,
                code: "content-system-version",
                message: "Compendium records were authored with system version \(contentVersion); the package manifest is \(manifest.version)."
            ))
        }

        diagnostics.append(FoundryImportDiagnostic(
            severity: .information,
            code: "rules-decoded",
            message: "Decoded \(totalDocuments) top-level rules from \(compendiums.count) compendiums."
        ))

        let assetPaths = FoundryAssetCollector.paths(in: compendiums).sorted()
        let resources = try FoundryPackageResourceResolver.resolve(
            assetPaths: assetPaths,
            systemID: manifest.id,
            basePath: basePath,
            source: source,
            limits: limits
        )
        let licensePaths = source.paths
            .filter { !$0.hasSuffix("/") && FoundryPackagePath.isLicensePath($0) }
            .sorted()
        var totalTextResourceBytes = 0
        var licenseDocuments: [FoundryPackageTextResource] = []
        for path in licensePaths {
            try Task.checkCancellation()
            guard let data = try source.data(forPath: path) else { continue }
            try consumeTextResourceBytes(
                data.count,
                total: &totalTextResourceBytes,
                maximum: limits.maximumRuleDataSize
            )
            guard let content = String(data: data, encoding: .utf8) else { continue }
            licenseDocuments.append(FoundryPackageTextResource(path: path, content: content))
        }
        let localizations = try FoundryLocalizationDecoder().decode(
            manifest: manifest,
            basePath: basePath,
            source: source,
            totalTextResourceBytes: &totalTextResourceBytes,
            maximumTextResourceBytes: limits.maximumRuleDataSize
        )
        return FoundryRulePackage(
            sourceSHA256: source.sourceSHA256,
            manifest: manifest,
            manifestPath: manifestPath,
            templatePath: templatePath,
            templateData: decodedTemplate,
            schemas: schemas,
            compendiums: compendiums,
            localizations: localizations,
            assetPaths: assetPaths,
            resources: resources,
            licensePaths: licensePaths,
            licenseDocuments: licenseDocuments,
            diagnostics: diagnostics
        )
    }

    static func consumeTextResourceBytes(
        _ byteCount: Int,
        total: inout Int,
        maximum: Int
    ) throws {
        let (nextTotal, overflow) = total.addingReportingOverflow(byteCount)
        guard !overflow, nextTotal <= maximum else {
            throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextTotal)
        }
        total = nextTotal
    }
}

private enum FoundryPackageDataSource: Sendable {
    case archive(FoundryZIPArchive, sourceSHA256: String)
    case directory(root: URL, paths: [String], pathSet: Set<String>, limits: FoundryImportLimits)

    init(url: URL, limits: FoundryImportLimits) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values.isDirectory == true {
            let root = url.standardizedFileURL.resolvingSymlinksInPath()
            let paths = try Self.directoryPaths(at: root, limits: limits)
            self = .directory(root: root, paths: paths, pathSet: Set(paths), limits: limits)
            return
        }

        if url.lastPathComponent.lowercased() == "system.json" {
            throw FoundryImportError.bareManifestRequiresContainer(url.lastPathComponent)
        }

        guard let fileSize = values.fileSize, fileSize <= limits.maximumArchiveSize else {
            throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
        }
        try Task.checkCancellation()
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try Task.checkCancellation()
        let digest = foundrySHA256(data)
        self = .archive(try FoundryZIPArchive(data: data, limits: limits), sourceSHA256: digest)
    }

    var paths: [String] {
        switch self {
        case .archive(let archive, _): archive.entryPaths
        case .directory(_, let paths, _, _): paths
        }
    }

    func contains(path: String) -> Bool {
        switch self {
        case .archive(let archive, _): archive.contains(path: path)
        case .directory(_, _, let pathSet, _): pathSet.contains(path)
        }
    }

    func data(forPath path: String) throws -> Data? {
        switch self {
        case .archive(let archive, _):
            return try archive.data(forPath: path)
        case .directory(let root, _, let pathSet, let limits):
            guard pathSet.contains(path) else { return nil }
            let candidate = root.appending(path: path).standardizedFileURL.resolvingSymlinksInPath()
            let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
            guard candidate.path.hasPrefix(rootPath) else {
                throw FoundryImportError.invalidArchive("A package path escapes its selected directory.")
            }
            let values = try candidate.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
            guard values.isRegularFile == true else { return nil }
            guard let fileSize = values.fileSize, fileSize <= limits.maximumEntrySize else {
                throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
            }
            return try Data(contentsOf: candidate, options: .mappedIfSafe)
        }
    }

    var sourceSHA256: String? {
        switch self {
        case .archive(_, let sourceSHA256): sourceSHA256
        case .directory: nil
        }
    }

    func manifestPath() throws -> String {
        let candidates = paths.filter { path in
            path.split(separator: "/").last?.lowercased() == "system.json"
        }
        if candidates.contains("system.json") {
            return "system.json"
        }
        guard !candidates.isEmpty else { throw FoundryImportError.missingManifest }
        guard candidates.count == 1 else { throw FoundryImportError.ambiguousManifest }
        return candidates[0]
    }
}

private struct FoundryLocalizationDecoder {
    func decode(
        manifest: FoundrySystemManifest,
        basePath: String,
        source: FoundryPackageDataSource,
        totalTextResourceBytes: inout Int,
        maximumTextResourceBytes: Int
    ) throws -> [FoundryLocalizationCatalog] {
        let declarations = manifest.rawData["languages"]?.arrayValue ?? []
        var catalogs: [FoundryLocalizationCatalog] = []
        for declaration in declarations {
            try Task.checkCancellation()
            guard let object = declaration.objectValue,
                  let languageCode = object["lang"]?.stringValue,
                  let relativePath = object["path"]?.stringValue else { continue }
            let path = try FoundryPackagePath.join(basePath, relativePath)
            guard let data = try source.data(forPath: path) else { continue }
            try FoundrySystemPackageReader.consumeTextResourceBytes(
                data.count,
                total: &totalTextResourceBytes,
                maximum: maximumTextResourceBytes
            )
            let translations = try FoundryJSONDecoder.decode(data, context: path)
            catalogs.append(FoundryLocalizationCatalog(
                languageCode: languageCode,
                name: object["name"]?.stringValue ?? languageCode,
                path: path,
                translations: translations
            ))
        }
        return catalogs.sorted { $0.languageCode < $1.languageCode }
    }
}

private extension FoundryPackageDataSource {
    static func directoryPaths(at root: URL, limits: FoundryImportLimits) throws -> [String] {
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let canonicalRootPath = canonicalRoot.path.hasSuffix("/") ? canonicalRoot.path : canonicalRoot.path + "/"
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: canonicalRoot,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else {
            throw FoundryImportError.unsupportedSource
        }

        var paths: [String] = []
        for case let fileURL as URL in enumerator {
            try Task.checkCancellation()
            let values = try fileURL.resourceValues(forKeys: Set(keys))
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            let canonicalFileURL = fileURL.standardizedFileURL.resolvingSymlinksInPath()
            guard canonicalFileURL.path.hasPrefix(canonicalRootPath) else {
                throw FoundryImportError.invalidArchive("A package path escapes its selected directory.")
            }
            let relativePath = String(canonicalFileURL.path.dropFirst(canonicalRootPath.count))
            paths.append(try FoundryPackagePath.normalized(relativePath))
            guard paths.count <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(paths.count)
            }
        }
        return paths.sorted()
    }
}

private enum FoundryPackagePath {
    static func join(_ base: String, _ relative: String) throws -> String {
        let cleanedRelative = relative.hasPrefix("./") ? String(relative.dropFirst(2)) : relative
        return try normalized(base + cleanedRelative)
    }

    static func normalized(_ path: String) throws -> String {
        guard !path.isEmpty, !path.hasPrefix("/"), !path.hasPrefix("\\"), !path.contains("\\"), !path.contains("\0") else {
            throw FoundryImportError.invalidArchive("The package contains an unsafe path.")
        }
        var result: [Substring] = []
        for component in path.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".": continue
            case "..": throw FoundryImportError.invalidArchive("The package contains a path traversal component.")
            default: result.append(component)
            }
        }
        guard !result.isEmpty else {
            throw FoundryImportError.invalidArchive("The package contains an empty path.")
        }
        return result.joined(separator: "/")
    }

    static func isLicensePath(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.contains("license") || lowercased.contains("attribution") || lowercased.contains("copying")
    }
}

private struct FoundryManifestDecoder {
    func decode(_ data: Data) throws -> FoundrySystemManifest {
        let raw = try FoundryJSONDecoder.decode(data, context: "system.json")
        guard let object = raw.objectValue else {
            throw FoundryImportError.invalidManifest("The top-level value is not an object.")
        }
        guard let id = object["id"]?.stringValue, !id.isEmpty else {
            throw FoundryImportError.invalidManifest("The id field is missing.")
        }
        guard let title = object["title"]?.stringValue, !title.isEmpty else {
            throw FoundryImportError.invalidManifest("The title field is missing.")
        }
        guard let version = object["version"]?.scalarString, !version.isEmpty else {
            throw FoundryImportError.invalidManifest("The version field is missing.")
        }

        let compatibilityObject = object["compatibility"]?.objectValue ?? [:]
        let compatibility = FoundryCompatibility(
            minimum: compatibilityObject["minimum"]?.scalarString,
            verified: compatibilityObject["verified"]?.scalarString,
            maximum: compatibilityObject["maximum"]?.scalarString
        )

        let packValues = object["packs"]?.arrayValue ?? []
        var packs: [FoundryPackManifest] = []
        var packNames = Set<String>()
        var packPaths = Set<String>()
        for packValue in packValues {
            guard let pack = packValue.objectValue,
                  let name = pack["name"]?.stringValue,
                  !name.isEmpty,
                  let documentType = pack["type"]?.stringValue,
                  !documentType.isEmpty else {
                throw FoundryImportError.invalidManifest("A compendium declaration is incomplete.")
            }
            let path = pack["path"]?.stringValue ?? "./packs/\(name)"
            let normalizedPath = try FoundryPackagePath.normalized(
                path.hasPrefix("./") ? String(path.dropFirst(2)) : path
            )
            guard packNames.insert(name).inserted else {
                throw FoundryImportError.invalidManifest("The compendium name \(name) is declared more than once.")
            }
            guard packPaths.insert(normalizedPath).inserted else {
                throw FoundryImportError.invalidManifest("The compendium path \(path) is declared more than once.")
            }
            packs.append(FoundryPackManifest(
                name: name,
                label: pack["label"]?.stringValue ?? name,
                path: path,
                documentType: documentType,
                systemID: pack["system"]?.stringValue
            ))
        }

        return FoundrySystemManifest(
            id: id,
            title: title,
            description: object["description"]?.stringValue,
            version: version,
            compatibility: compatibility,
            packs: packs,
            rawData: raw
        )
    }
}

private enum FoundryJSONDecoder {
    static func decodeSource(_ data: Data) throws -> FoundryJSONValue {
        let decoder = JSONDecoder()
        decoder.userInfo[.masterRPGFoundrySourceJSON] = true
        decoder.userInfo[.masterRPGFoundryJSONDepth] = FoundryJSONDepthCounter()
        return try decoder.decode(FoundryJSONValue.self, from: data)
    }

    static func decode(_ data: Data, context: String) throws -> FoundryJSONValue {
        do {
            return try decodeSource(data)
        } catch {
            if context == "system.json" {
                throw FoundryImportError.invalidManifest(error.localizedDescription)
            }
            throw FoundryImportError.invalidArchive("\(context) is not valid JSON.")
        }
    }
}

private struct FoundryTemplateDecoder {
    func decode(_ template: FoundryJSONValue) throws -> [FoundryRuleSchema] {
        guard let root = template.objectValue else {
            throw FoundryImportError.invalidArchive("template.json is not an object.")
        }
        var schemas: [FoundryRuleSchema] = []
        for documentType in root.keys.sorted() {
            guard let document = root[documentType]?.objectValue else { continue }
            let templates = document["templates"]?.objectValue ?? [:]
            let declaredTypes = document["types"]?.arrayValue?.compactMap(\.stringValue) ?? []
            for subtype in declaredTypes.sorted() {
                guard let subtypeValue = document[subtype], let subtypeObject = subtypeValue.objectValue else { continue }
                let inherited = subtypeObject["templates"]?.arrayValue?.compactMap(\.stringValue) ?? []
                var resolved: [String: FoundryJSONValue] = [:]
                for templateName in inherited {
                    let inheritedValue = try resolveTemplate(
                        named: templateName,
                        templates: templates,
                        stack: []
                    )
                    resolved = deepMerge(resolved, inheritedValue)
                }
                resolved = deepMerge(resolved, subtypeObject.filter { $0.key != "templates" })
                schemas.append(FoundryRuleSchema(
                    documentType: documentType,
                    subtype: subtype,
                    inheritedTemplates: inherited,
                    fields: flatten(.object(resolved), path: ["system"]).map {
                        FoundryRuleField(path: $0.path, valueKind: $0.value.valueKind, defaultValue: $0.value)
                    },
                    rawData: subtypeValue
                ))
            }
        }
        return schemas.sorted { $0.id < $1.id }
    }
}

private extension FoundryTemplateDecoder {
    func resolveTemplate(
        named name: String,
        templates: [String: FoundryJSONValue],
        stack: Set<String>
    ) throws -> [String: FoundryJSONValue] {
        guard !stack.contains(name) else {
            throw FoundryImportError.invalidArchive("template.json contains an inheritance cycle at \(name).")
        }
        guard let value = templates[name], let object = value.objectValue else {
            throw FoundryImportError.invalidArchive("template.json references missing template \(name).")
        }
        var nextStack = stack
        nextStack.insert(name)
        let inherited = object["templates"]?.arrayValue?.compactMap(\.stringValue) ?? []
        var result: [String: FoundryJSONValue] = [:]
        for parent in inherited {
            result = deepMerge(result, try resolveTemplate(named: parent, templates: templates, stack: nextStack))
        }
        return deepMerge(result, object.filter { $0.key != "templates" })
    }

    func deepMerge(
        _ base: [String: FoundryJSONValue],
        _ overlay: [String: FoundryJSONValue]
    ) -> [String: FoundryJSONValue] {
        var result = base
        for (key, value) in overlay {
            if let existing = result[key]?.objectValue, let newValue = value.objectValue {
                result[key] = .object(deepMerge(existing, newValue))
            } else {
                result[key] = value
            }
        }
        return result
    }
}

private struct FoundryCompendiumDecoder {
    struct Result {
        let compendium: FoundryCompendium
        let diagnostics: [FoundryImportDiagnostic]
    }

    let systemID: String
    let pack: FoundryPackManifest
    let maximumDocumentCount: Int

    func decode(_ records: [FoundryLevelDBRecord]) throws -> Result {
        var latest: [String: FoundryLevelDBRecord] = [:]
        for record in records {
            if let current = latest[record.key] {
                if current.sequence > record.sequence { continue }
                if current.sequence == record.sequence {
                    guard current.operation == record.operation, current.value == record.value else {
                        throw FoundryImportError.corruptLevelDB("A key has conflicting records at the same sequence number.")
                    }
                    continue
                }
            }
            latest[record.key] = record
        }
        let activeRecords = latest.values
            .filter { $0.operation == .value }
            .sorted { $0.key < $1.key }
        guard activeRecords.count <= maximumDocumentCount else {
            throw FoundryImportError.tooManyDocuments(activeRecords.count)
        }

        var topDocuments: [String: (type: String, raw: FoundryJSONValue)] = [:]
        var embeddedItems: [String: [String: FoundryJSONValue]] = [:]
        var actorEffects: [String: [String: FoundryJSONValue]] = [:]
        var itemEffects: [String: [String: FoundryJSONValue]] = [:]
        var embeddedItemEffects: [String: [String: [String: FoundryJSONValue]]] = [:]
        var folders: [FoundryFolder] = []
        var unknownKeys: [String] = []

        for record in activeRecords {
            let raw: FoundryJSONValue
            do {
                raw = try FoundryJSONDecoder.decodeSource(record.value)
            } catch {
                throw FoundryImportError.invalidDocument(pack: pack.name, key: record.key)
            }
            if let id = record.key.suffix(after: "!items!") {
                topDocuments[id] = ("Item", raw)
            } else if let id = record.key.suffix(after: "!actors!") {
                topDocuments[id] = ("Actor", raw)
            } else if let suffix = record.key.suffix(after: "!actors.items.effects!"),
                      let parts = suffix.foundryIDComponents(expectedCount: 3) {
                embeddedItemEffects[parts[0], default: [:]][parts[1], default: [:]][parts[2]] = raw
            } else if let suffix = record.key.suffix(after: "!actors.items!"),
                      let parts = suffix.foundryIDComponents(expectedCount: 2) {
                embeddedItems[parts[0], default: [:]][parts[1]] = raw
            } else if let suffix = record.key.suffix(after: "!actors.effects!"),
                      let parts = suffix.foundryIDComponents(expectedCount: 2) {
                actorEffects[parts[0], default: [:]][parts[1]] = raw
            } else if let suffix = record.key.suffix(after: "!items.effects!"),
                      let parts = suffix.foundryIDComponents(expectedCount: 2) {
                itemEffects[parts[0], default: [:]][parts[1]] = raw
            } else if let id = record.key.suffix(after: "!folders!") {
                folders.append(decodeFolder(id: id, raw: raw))
            } else {
                unknownKeys.append(record.key)
            }
        }

        let rules = topDocuments.map { documentID, document in
            let canonicalID = FoundryCanonicalKey.topLevel(
                systemID: systemID,
                packName: pack.name,
                documentType: document.type,
                documentID: documentID
            )
            let actorEmbeddedEffects: [String: [String: FoundryJSONValue]] = embeddedItemEffects[documentID] ?? [:]
            var embedded: [FoundryEmbeddedRule] = []
            for (itemID, raw) in embeddedItems[documentID, default: [:]] {
                let embeddedID = FoundryCanonicalKey.embedded(parent: canonicalID, documentType: "Item", documentID: itemID)
                let rawItemEffects: [String: FoundryJSONValue] = actorEmbeddedEffects[itemID] ?? [:]
                let effects = decodeEffects(
                    rawItemEffects,
                    ownerCanonicalID: embeddedID
                )
                embedded.append(decodeEmbeddedRule(id: embeddedID, fallbackID: itemID, raw: raw, effects: effects))
            }
            embedded.sort { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
            let rawEffects = document.type == "Actor"
                ? actorEffects[documentID, default: [:]]
                : itemEffects[documentID, default: [:]]
            let effects = decodeEffects(rawEffects, ownerCanonicalID: canonicalID)
            return decodeRule(
                canonicalID: canonicalID,
                fallbackID: documentID,
                documentType: document.type,
                raw: document.raw,
                embeddedRules: embedded,
                effects: effects
            )
        }.sorted { lhs, rhs in
            let lhsSort = lhs.rawData["sort"]?.integerValue ?? 0
            let rhsSort = rhs.rawData["sort"]?.integerValue ?? 0
            if lhsSort != rhsSort { return lhsSort < rhsSort }
            if lhs.name != rhs.name { return lhs.name < rhs.name }
            return lhs.id < rhs.id
        }

        var diagnostics: [FoundryImportDiagnostic] = []
        if !unknownKeys.isEmpty {
            diagnostics.append(FoundryImportDiagnostic(
                severity: .warning,
                code: "unknown-leveldb-records",
                message: "Preserved the supported rules but skipped \(unknownKeys.count) unrecognized LevelDB records.",
                packName: pack.name
            ))
        }
        return Result(
            compendium: FoundryCompendium(
                manifest: pack,
                rules: rules,
                folders: folders.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
            ),
            diagnostics: diagnostics
        )
    }
}

private extension FoundryCompendiumDecoder {
    func decodeRule(
        canonicalID: String,
        fallbackID: String,
        documentType: String,
        raw: FoundryJSONValue,
        embeddedRules: [FoundryEmbeddedRule],
        effects: [FoundryRuleEffect]
    ) -> FoundryRuleDefinition {
        let documentID = raw["_id"]?.stringValue ?? fallbackID
        let subtype = raw["type"]?.stringValue ?? documentType.lowercased()
        let system = raw["system"] ?? .object([:])
        let description = system["description"]?.stringValue
        return FoundryRuleDefinition(
            id: canonicalID,
            documentID: documentID,
            packName: pack.name,
            documentType: documentType,
            subtype: subtype,
            category: FoundryRuleCategory.category(systemID: systemID, documentType: documentType, subtype: subtype),
            name: raw["name"]?.stringValue ?? documentID,
            descriptionHTML: description,
            imagePath: raw["img"]?.stringValue,
            folderID: raw["folder"]?.stringValue,
            values: flatten(system, path: ["system"]),
            tags: tags(documentType: documentType, subtype: subtype, system: system),
            references: FoundryReferenceDecoder.decode(in: raw),
            embeddedRules: embeddedRules,
            effects: effects,
            rawData: raw
        )
    }

    func decodeEmbeddedRule(
        id: String,
        fallbackID: String,
        raw: FoundryJSONValue,
        effects: [FoundryRuleEffect]
    ) -> FoundryEmbeddedRule {
        let documentID = raw["_id"]?.stringValue ?? fallbackID
        let subtype = raw["type"]?.stringValue ?? "item"
        return FoundryEmbeddedRule(
            id: id,
            name: raw["name"]?.stringValue ?? documentID,
            subtype: subtype,
            category: FoundryRuleCategory.category(systemID: systemID, documentType: "Item", subtype: subtype),
            descriptionHTML: raw.value(at: "system.description")?.stringValue,
            imagePath: raw["img"]?.stringValue,
            values: flatten(raw["system"] ?? .object([:]), path: ["system"]),
            references: FoundryReferenceDecoder.decode(in: raw),
            effects: effects,
            rawData: raw
        )
    }

    func decodeEffects(
        _ rawEffects: [String: FoundryJSONValue],
        ownerCanonicalID: String
    ) -> [FoundryRuleEffect] {
        rawEffects.map { fallbackID, raw in
            let effectID = raw["_id"]?.stringValue ?? fallbackID
            let canonicalID = FoundryCanonicalKey.embedded(
                parent: ownerCanonicalID,
                documentType: "ActiveEffect",
                documentID: effectID
            )
            let statuses = raw["statuses"]?.arrayValue?.compactMap(\.stringValue) ?? []
            let changes = raw["changes"]?.arrayValue?.compactMap { change -> FoundryRuleEffectChange? in
                guard let object = change.objectValue, let path = object["key"]?.stringValue else { return nil }
                return FoundryRuleEffectChange(
                    path: path,
                    mode: object["mode"]?.integerValue ?? 0,
                    operand: object["value"] ?? .null,
                    priority: object["priority"]?.integerValue
                )
            } ?? []
            return FoundryRuleEffect(
                id: canonicalID,
                name: raw["name"]?.stringValue ?? effectID,
                isDisabled: raw["disabled"]?.boolValue ?? false,
                transfersToActor: raw["transfer"]?.boolValue ?? false,
                statuses: statuses,
                changes: changes,
                duration: raw["duration"],
                rawData: raw
            )
        }.sorted { $0.name == $1.name ? $0.id < $1.id : $0.name < $1.name }
    }

    func decodeFolder(id: String, raw: FoundryJSONValue) -> FoundryFolder {
        FoundryFolder(
            id: raw["_id"]?.stringValue ?? id,
            name: raw["name"]?.stringValue ?? id,
            parentID: raw["folder"]?.stringValue,
            sort: raw["sort"]?.integerValue
        )
    }

    func tags(documentType: String, subtype: String, system: FoundryJSONValue) -> [String] {
        guard systemID == "ds4" else { return [] }
        var tags: [String] = []
        if subtype == "spell", let groups = system["spellGroups"]?.objectValue {
            tags.append(contentsOf: groups.compactMap { $0.value.boolValue == true ? $0.key : nil })
        }
        if documentType == "Actor" {
            if let type = system.value(at: "baseInfo.creatureType")?.stringValue, !type.isEmpty {
                tags.append("creatureType:\(type)")
            }
            if let size = system.value(at: "baseInfo.sizeCategory")?.stringValue, !size.isEmpty {
                tags.append("size:\(size)")
            }
        }
        return Array(Set(tags)).sorted()
    }
}

private enum FoundryCanonicalKey {
    static func topLevel(systemID: String, packName: String, documentType: String, documentID: String) -> String {
        "foundry://system/\(component(systemID))/pack/\(component(packName))/\(component(documentType))/\(component(documentID))"
    }

    static func embedded(parent: String, documentType: String, documentID: String) -> String {
        "\(parent)/\(component(documentType))/\(component(documentID))"
    }

    private static func component(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

enum FoundryReferenceDecoder {
    static func decode(in raw: FoundryJSONValue) -> [FoundryRuleReference] {
        var references: [FoundryRuleReference] = []
        visit(raw, path: [], references: &references)
        return Array(Set(references)).sorted {
            if $0.sourcePath != $1.sourcePath { return $0.sourcePath < $1.sourcePath }
            return $0.rawToken < $1.rawToken
        }
    }

    private static func visit(
        _ value: FoundryJSONValue,
        path: [String],
        references output: inout [FoundryRuleReference]
    ) {
        switch value {
        case .object(let object):
            for key in object.keys.sorted() {
                if let child = object[key] {
                    visit(child, path: path + [key], references: &output)
                }
            }
        case .array(let values):
            for (index, child) in values.enumerated() {
                visit(child, path: path + [String(index)], references: &output)
            }
        case .string(let string):
            output.append(contentsOf: references(in: string, sourcePath: path.joined(separator: ".")))
        default:
            break
        }
    }

    private static func references(in text: String, sourcePath: String) -> [FoundryRuleReference] {
        let markers: [(String, FoundryRuleReference.Kind)] = [
            ("@Compendium[", .compendium),
            ("@UUID[", .uuid),
            ("@Actor[", .document),
            ("@Item[", .document),
            ("@JournalEntry[", .document),
            ("@RollTable[", .document)
        ]
        var result: [FoundryRuleReference] = []
        for (marker, kind) in markers {
            var searchStart = text.startIndex
            while let markerRange = text.range(of: marker, range: searchStart..<text.endIndex),
                  let closingBracket = text[markerRange.upperBound...].firstIndex(of: "]") {
                let target = String(text[markerRange.upperBound..<closingBracket])
                var tokenEnd = text.index(after: closingBracket)
                var label: String?
                if tokenEnd < text.endIndex, text[tokenEnd] == "{",
                   let closingBrace = text[text.index(after: tokenEnd)...].firstIndex(of: "}") {
                    label = String(text[text.index(after: tokenEnd)..<closingBrace])
                    tokenEnd = text.index(after: closingBrace)
                }
                let rawToken = String(text[markerRange.lowerBound..<tokenEnd])
                let components = target.split(separator: ".").map(String.init)
                let unpacked = unpackTarget(components, kind: kind)
                result.append(FoundryRuleReference(
                    kind: kind,
                    sourcePath: sourcePath,
                    rawToken: rawToken,
                    target: target,
                    label: label,
                    packName: unpacked.pack,
                    documentID: unpacked.documentID
                ))
                searchStart = tokenEnd
            }
        }

        if text.hasPrefix("Compendium."), !text.contains(where: \Character.isWhitespace) {
            let components = text.split(separator: ".").map(String.init)
            let unpacked = unpackTarget(components, kind: .uuid)
            result.append(FoundryRuleReference(
                kind: .uuid,
                sourcePath: sourcePath,
                rawToken: text,
                target: text,
                label: nil,
                packName: unpacked.pack,
                documentID: unpacked.documentID
            ))
        }
        return result
    }

    private static func unpackTarget(
        _ components: [String],
        kind: FoundryRuleReference.Kind
    ) -> (pack: String?, documentID: String?) {
        if components.first == "Compendium", components.count >= 4 {
            return (components[2], components.last)
        }
        if kind == .compendium, components.count >= 3 {
            return (components[1], components.last)
        }
        return (nil, components.last)
    }
}

private enum FoundryAssetCollector {
    private static let extensions = Set([
        "aac", "aif", "aiff", "apng", "avif", "bmp", "caf", "flac", "gif", "glb", "gltf",
        "heic", "heif", "jpeg", "jpg", "m4a", "mp3", "mp4", "oga", "ogg", "opus", "pdf",
        "png", "svg", "tif", "tiff", "usdz", "wav", "webm", "webp"
    ])

    static func paths(in compendiums: [FoundryCompendium]) -> Set<String> {
        var result = Set<String>()
        for rule in compendiums.flatMap(\.rules) {
            collect(rule.rawData, into: &result)
            for effect in rule.effects {
                collect(effect.rawData, into: &result)
            }
            for embedded in rule.embeddedRules {
                collect(embedded.rawData, into: &result)
                for effect in embedded.effects {
                    collect(effect.rawData, into: &result)
                }
            }
        }
        return result
    }

    private static func collect(_ value: FoundryJSONValue, into result: inout Set<String>) {
        switch value {
        case .object(let object):
            for child in object.values { collect(child, into: &result) }
        case .array(let values):
            for child in values { collect(child, into: &result) }
        case .string(let string):
            let pathWithoutFragment = string.split(
                separator: "#",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )[0]
            let pathWithoutQuery = pathWithoutFragment.split(
                separator: "?",
                maxSplits: 1,
                omittingEmptySubsequences: false
            )[0]
            let pathExtension = URL(fileURLWithPath: String(pathWithoutQuery)).pathExtension.lowercased()
            if extensions.contains(pathExtension) { result.insert(string) }
        default:
            break
        }
    }
}

private enum FoundryPackageResourceResolver {
    static func resolve(
        assetPaths: [String],
        systemID: String,
        basePath: String,
        source: FoundryPackageDataSource,
        limits: FoundryImportLimits
    ) throws -> [FoundryPackageResource] {
        var totalPackagedBytes = 0
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

            for candidate in packageCandidates(
                for: logicalPath,
                systemID: systemID,
                basePath: basePath
            ) where source.contains(path: candidate) {
                guard let data = try source.data(forPath: candidate) else { continue }
                let (nextPackagedBytes, overflow) = totalPackagedBytes.addingReportingOverflow(data.count)
                guard !overflow, nextPackagedBytes <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : nextPackagedBytes)
                }
                totalPackagedBytes = nextPackagedBytes
                return FoundryPackageResource(
                    logicalPath: logicalPath,
                    packagePath: candidate,
                    location: .packaged,
                    byteCount: data.count,
                    sha256: foundrySHA256(data)
                )
            }

            let location: FoundryPackageResource.Location = isFoundryInstallationPath(logicalPath)
                ? .foundryInstallation
                : .unresolved
            return FoundryPackageResource(
                logicalPath: logicalPath,
                packagePath: nil,
                location: location,
                byteCount: nil,
                sha256: nil
            )
        }
    }

    private static func packageCandidates(
        for logicalPath: String,
        systemID: String,
        basePath: String
    ) -> [String] {
        let path = logicalPath
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0]
        let cleanedPath = String(path)
        var candidates: [String] = []

        let systemPrefix = "systems/\(systemID)/"
        if cleanedPath.hasPrefix(systemPrefix) {
            let relative = String(cleanedPath.dropFirst(systemPrefix.count))
            if let mapped = try? FoundryPackagePath.join(basePath, relative) {
                candidates.append(mapped)
            }
            if let normalized = try? FoundryPackagePath.normalized(cleanedPath) {
                candidates.append(normalized)
            }
        } else if basePath.isEmpty {
            if let normalized = try? FoundryPackagePath.normalized(cleanedPath) {
                candidates.append(normalized)
            }
        } else if let mapped = try? FoundryPackagePath.join(basePath, cleanedPath) {
            candidates.append(mapped)
        }
        var seen = Set<String>()
        return candidates.filter { seen.insert($0).inserted }
    }

    private static func isRemote(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return lowercased.hasPrefix("https://") || lowercased.hasPrefix("http://")
    }

    private static func isFoundryInstallationPath(_ path: String) -> Bool {
        ["icons/", "modules/", "systems/", "ui/", "worlds/"].contains { path.hasPrefix($0) }
    }
}

private func flatten(_ value: FoundryJSONValue, path: [String]) -> [FoundryRuleValue] {
    switch value {
    case .object(let object) where !object.isEmpty:
        return object.keys.sorted().flatMap { key in
            flatten(object[key] ?? .null, path: path + [key])
        }
    default:
        return [FoundryRuleValue(path: path.joined(separator: "."), value: value)]
    }
}

func foundrySHA256(_ data: Data) -> String {
    SHA256.hash(data: data)
        .map { String($0, radix: 16).leftPadded(to: 2, with: "0") }
        .joined()
}

private extension FoundryJSONValue {
    var scalarString: String? {
        switch self {
        case .string(let value): value
        case .integer(let value): String(value)
        case .unsignedInteger(let value): String(value)
        case .number(let value): String(value)
        default: nil
        }
    }

    var valueKind: FoundryRuleField.ValueKind {
        switch self {
        case .object: .object
        case .array: .array
        case .string: .string
        case .integer: .integer
        case .unsignedInteger: .unsignedInteger
        case .number: .number
        case .bool: .boolean
        case .null: .null
        }
    }
}

private extension FoundryRuleCategory {
    static func category(systemID: String, documentType: String, subtype: String) -> Self {
        guard systemID == "ds4" else { return Self(rawValue: subtype) }
        return switch subtype {
        case "character": .character
        case "creature": .creature
        case "spell": .spell
        case "talent": .talent
        case "weapon": .weapon
        case "armor": .armor
        case "shield": .shield
        case "equipment": .equipment
        case "loot": .loot
        case "racialAbility": .ancestryAbility
        case "language": .language
        case "alphabet": .script
        case "specialCreatureAbility": .creatureAbility
        default: Self(rawValue: subtype.isEmpty ? documentType.lowercased() : subtype)
        }
    }
}

private extension String {
    func suffix(after prefix: String) -> String? {
        guard hasPrefix(prefix) else { return nil }
        return String(dropFirst(prefix.count))
    }

    func foundryIDComponents(expectedCount: Int) -> [String]? {
        let components = split(separator: ".", omittingEmptySubsequences: false).map(String.init)
        guard components.count == expectedCount, components.allSatisfy({ !$0.isEmpty }) else { return nil }
        return components
    }

    func leftPadded(to length: Int, with character: Character) -> String {
        guard count < length else { return self }
        return String(repeating: String(character), count: length - count) + self
    }

}
