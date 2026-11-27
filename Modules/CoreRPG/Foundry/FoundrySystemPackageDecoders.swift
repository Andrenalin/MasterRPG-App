// @copyright André Trettin

import CryptoKit
import Foundation

// The manifest, localization, template and reference decoders, split out of FoundrySystemPackageReader.swift. See CODE_AUDIT_29 §9.9.

struct FoundryLocalizationDecoder {
    func decode(
        manifest: FoundrySystemManifest,
        basePath: String,
        source: FoundryVTTDataSource,
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
            let translations = try FoundryJSONDecoding.decode(data, context: path)
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

struct FoundryManifestDecoder {
    func decode(_ data: Data) throws -> FoundrySystemManifest {
        let raw = try FoundryJSONDecoding.decode(data, context: "system.json", isManifestContext: true)
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
                systemId: pack["system"]?.stringValue
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

struct FoundryTemplateDecoder {
    /// Longest inheritance chain accepted. Real systems nest a handful of levels; a chain of
    /// thousands recursed one stack frame per level and could overflow the worker's stack.
    /// See CODE_AUDIT_26 §6.1.
    static let maximumInheritanceDepth = 32
    /// Most templates one `template.json` may declare.
    static let maximumTemplateCount = 4_096

    /// Every subtype gets its own flattened copy of its templates' fields, so thousands of
    /// subtypes times thousands of fields would be millions of entries from a few MiB of JSON.
    /// Real systems declare tens of subtypes and a few thousand fields in total.
    /// See CODE_AUDIT §6.2.
    static let maximumSubtypeCount = 1_024
    static let maximumTotalFieldCount = 500_000

    /// The list without repeated names. The last occurrence stays: merging a template twice gives
    /// the same result as merging it once at its last position, and a repeated name would
    /// otherwise double the work of every level above it.
    static func deduplicated(_ names: [String]) -> [String] {
        var seen: Set<String> = []
        return names.reversed().filter { seen.insert($0).inserted }.reversed()
    }

    func decode(_ template: FoundryJSONValue) throws -> [FoundryRuleSchema] {
        guard let root = template.objectValue else {
            throw FoundryImportError.invalidArchive("template.json is not an object.")
        }
        var schemas: [FoundryRuleSchema] = []
        var totalSubtypeCount = 0
        var totalFieldCount = 0
        for documentType in root.keys.sorted() {
            guard let document = root[documentType]?.objectValue else { continue }
            let templates = document["templates"]?.objectValue ?? [:]
            guard templates.count <= Self.maximumTemplateCount else {
                throw FoundryImportError.invalidArchive("template.json declares more than \(Self.maximumTemplateCount) templates.")
            }
            // Each template is resolved once for the whole document type, however many
            // templates and subtypes list it.
            var memo: [String: [String: FoundryJSONValue]] = [:]
            let declaredTypes = document["types"]?.arrayValue?.compactMap(\.stringValue) ?? []
            totalSubtypeCount += declaredTypes.count
            guard totalSubtypeCount <= Self.maximumSubtypeCount else {
                throw FoundryImportError.invalidArchive("template.json declares more than \(Self.maximumSubtypeCount) subtypes.")
            }
            for subtype in declaredTypes.sorted() {
                guard let subtypeValue = document[subtype], let subtypeObject = subtypeValue.objectValue else { continue }
                let inherited = Self.deduplicated(subtypeObject["templates"]?.arrayValue?.compactMap(\.stringValue) ?? [])
                var resolved: [String: FoundryJSONValue] = [:]
                for templateName in inherited {
                    let inheritedValue = try resolveTemplate(
                        named: templateName,
                        templates: templates,
                        stack: [],
                        memo: &memo
                    )
                    resolved = deepMerge(resolved, inheritedValue)
                }
                resolved = deepMerge(resolved, subtypeObject.filter { $0.key != "templates" })
                let fields = flatten(.object(resolved), path: ["system"]).map {
                    FoundryRuleField(path: $0.path, valueKind: $0.value.valueKind, defaultValue: $0.value)
                }
                totalFieldCount += fields.count
                guard totalFieldCount <= Self.maximumTotalFieldCount else {
                    throw FoundryImportError.invalidArchive("template.json expands to more than \(Self.maximumTotalFieldCount) fields.")
                }
                schemas.append(FoundryRuleSchema(
                    documentType: documentType,
                    subtype: subtype,
                    inheritedTemplates: inherited,
                    fields: fields,
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
        stack: Set<String>,
        memo: inout [String: [String: FoundryJSONValue]]
    ) throws -> [String: FoundryJSONValue] {
        try Task.checkCancellation()
        if let cached = memo[name] { return cached }
        guard !stack.contains(name) else {
            throw FoundryImportError.invalidArchive("template.json contains an inheritance cycle at \(name).")
        }
        guard stack.count < Self.maximumInheritanceDepth else {
            throw FoundryImportError.invalidArchive("template.json nests templates deeper than \(Self.maximumInheritanceDepth) levels at \(name).")
        }
        guard let value = templates[name], let object = value.objectValue else {
            throw FoundryImportError.invalidArchive("template.json references missing template \(name).")
        }
        var nextStack = stack
        nextStack.insert(name)
        let inherited = Self.deduplicated(object["templates"]?.arrayValue?.compactMap(\.stringValue) ?? [])
        var result: [String: FoundryJSONValue] = [:]
        for parent in inherited {
            result = deepMerge(result, try resolveTemplate(named: parent, templates: templates, stack: nextStack, memo: &memo))
        }
        result = deepMerge(result, object.filter { $0.key != "templates" })
        memo[name] = result
        return result
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
                    documentId: unpacked.documentId
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
                documentId: unpacked.documentId
            ))
        }
        return result
    }

    private static func unpackTarget(
        _ components: [String],
        kind: FoundryRuleReference.Kind
    ) -> (pack: String?, documentId: String?) {
        if components.first == "Compendium", components.count >= 4 {
            return (components[2], components.last)
        }
        if kind == .compendium, components.count >= 3 {
            return (components[1], components.last)
        }
        return (nil, components.last)
    }
}
