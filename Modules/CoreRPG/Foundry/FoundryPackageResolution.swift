// @copyright André Trettin

import Foundation

// This file consolidates logic that was previously duplicated, with drift, across
// `FoundryVTTImportReader.swift` (world/module/exported-document imports) and
// `FoundrySystemPackageReader.swift` (system-package imports). See CODE_AUDIT §9.1-§9.5.

// MARK: - Package Path Utilities (CODE_AUDIT §9.2, §9.5)

/// Path-traversal-safe normalization and joining for paths referenced inside a Foundry
/// package (world, module, system, or exported-document archive/directory).
enum FoundryPackagePath {
    /// Percent-encodes one identifier path component (unreserved characters only). Shared by the
    /// world and system readers, which each carried an identical copy. See CODE_AUDIT_15 §9.10.
    static func encodedComponent(_ value: String) -> String {
        let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }

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

    /// Reconciles the two prior copies' behavior: excludes directory-like paths (a trailing
    /// `/` — a "license/" folder is not itself a license file) and matches
    /// "license"/"copying"/"attribution" anywhere in the lowercased path.
    static func isLicensePath(_ path: String) -> Bool {
        let lowercased = path.lowercased()
        return !lowercased.hasSuffix("/")
            && (lowercased.contains("license") || lowercased.contains("copying") || lowercased.contains("attribution"))
    }
}

// MARK: - JSON Decoding (CODE_AUDIT §9.3)

/// Decodes Foundry-authored JSON with the anti-DoS depth guard (`FoundryJSONDepthCounter`)
/// installed — kept in exactly one place so a future tightening of the guard can't land in
/// only one of the two readers.
enum FoundryJSONDecoding {
    static func decodeSource(_ data: Data) throws -> FoundryJSONValue {
        let decoder = JSONDecoder()
        decoder.userInfo[.masterRPGFoundrySourceJSON] = true
        decoder.userInfo[.masterRPGFoundryJSONDepth] = FoundryJSONDepthCounter()
        return try decoder.decode(FoundryJSONValue.self, from: data)
    }

    /// Decodes `data`, translating any failure into a `FoundryImportError`. Pass
    /// `isManifestContext: true` when `context` names a manifest file (e.g. "system.json") to
    /// get the more specific `.invalidManifest` instead of the generic `.invalidArchive` —
    /// preserves `FoundrySystemPackageReader`'s existing manifest-specific error message.
    static func decode(_ data: Data, context: String, isManifestContext: Bool = false) throws -> FoundryJSONValue {
        do {
            return try decodeSource(data)
        } catch {
            if isManifestContext {
                throw FoundryImportError.invalidManifest(error.localizedDescription)
            }
            throw FoundryImportError.invalidArchive("\(context) is not valid JSON.")
        }
    }
}

// MARK: - Asset Path Collection (CODE_AUDIT §9.4)

/// Walks a Foundry document/compendium's raw JSON looking for asset references — both plain
/// string values with a recognized media extension, and `src`/`href` attributes inside inline
/// HTML fragments (journal/description text often embeds `<img>`/`<audio>` tags).
enum FoundryAssetPathCollector {
    /// The superset of the two prior copies' extension lists — the system-package copy was
    /// missing `m4v` and `ogv`, which meant it classified those two file types differently
    /// from the world-import copy.
    static let pathExtensions = Set([
        "aac", "aif", "aiff", "apng", "avif", "bmp", "caf", "flac", "gif", "glb", "gltf",
        "heic", "heif", "jpeg", "jpg", "m4a", "m4v", "mp3", "mp4", "oga", "ogg", "ogv",
        "opus", "pdf", "png", "svg", "tif", "tiff", "usdz", "wav", "webm", "webp",
    ])

    static func paths(in rawValues: some Sequence<FoundryJSONValue>) -> Set<String> {
        var result = Set<String>()
        for value in rawValues { collect(value, into: &result) }
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

// MARK: - Package Resource Resolution (CODE_AUDIT §9.1, §6.1)

/// Resolves each logical asset path referenced by a Foundry package into a `.remote`,
/// `.packaged`, `.foundryInstallation`, or `.unresolved` `FoundryPackageResource`.
///
/// The two prior copies of this ~85-line algorithm had already drifted: the system-package
/// copy's `isRemote` didn't recognize `data:` URIs (fixed separately per CODE_AUDIT §6.1
/// before this merge removed the duplicate), and its candidate-path fallback used an
/// either/or `if/else` where the world-import copy tried every candidate unconditionally —
/// this merge adopts the world-import copy's strictly broader (never narrower) behavior for
/// both callers.
///
/// `contains`/`data` are closures rather than a shared source protocol because the two
/// readers' data-source types (`FoundryVTTDataSource`, `FoundryPackageDataSource`) are each
/// `private` to their own file.
enum FoundryPackageResourceResolver {
    static func resolve(
        assetPaths: [String],
        packageDirectory: String?,
        packageID: String,
        basePath: String,
        contains: (String) -> Bool,
        data: (String) throws -> Data?,
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
                packageDirectory: packageDirectory,
                packageID: packageID,
                basePath: basePath
            ) where contains(candidate) {
                guard let resolvedData = try data(candidate) else { continue }
                let (next, overflow) = packagedBytes.addingReportingOverflow(resolvedData.count)
                guard !overflow, next <= limits.maximumResourceBatchSize else {
                    throw FoundryImportError.fileTooLarge(overflow ? Int.max : next)
                }
                packagedBytes = next
                return FoundryPackageResource(
                    logicalPath: logicalPath,
                    packagePath: candidate,
                    location: .packaged,
                    byteCount: resolvedData.count,
                    sha256: foundrySHA256(resolvedData)
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
        packageDirectory: String?,
        packageID: String,
        basePath: String
    ) -> [String] {
        let encodedPath = String(logicalPath
            .split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false)[0]
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)[0])
        // Decode once, then apply package-path validation. Encoded separators and `..` therefore
        // become visible to the traversal checks instead of being passed to filesystem lookup.
        guard let clean = encodedPath.removingPercentEncoding else { return [] }
        var result: [String] = []
        if let packageDirectory {
            let prefix = "\(packageDirectory)/\(packageID)/"
            if clean.hasPrefix(prefix),
               let mapped = try? FoundryPackagePath.join(basePath, String(clean.dropFirst(prefix.count))) {
                result.append(mapped)
            }
        }
        if let normalized = try? FoundryPackagePath.normalized(clean) { result.append(normalized) }
        if !basePath.isEmpty, let mapped = try? FoundryPackagePath.join(basePath, clean) { result.append(mapped) }
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
