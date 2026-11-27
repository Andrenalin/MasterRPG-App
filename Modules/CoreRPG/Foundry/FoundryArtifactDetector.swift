// @copyright André Trettin

import Foundation

/// The artifact syntax identified before presenting an import workflow.
public enum FoundryArtifactKind: String, Codable, Equatable, Sendable {
    case systemPackage
    case modulePackage
    case worldPackage
    case exportedDocument
    case documentDatabase
    case universalVTT
    case masterRPGBridge
    case unknown
}

public struct FoundryArtifact: Codable, Equatable, Sendable {
    public let kind: FoundryArtifactKind
    public let suggestedName: String

    public init(kind: FoundryArtifactKind, suggestedName: String) {
        self.kind = kind
        self.suggestedName = suggestedName
    }
}

/// Performs bounded, read-only format detection. It never evaluates package JavaScript or HTML.
public struct FoundryArtifactDetector: Sendable {
    public let limits: FoundryImportLimits

    public init(limits: FoundryImportLimits = .default) {
        self.limits = limits
    }

    public func detect(at url: URL) throws -> FoundryArtifact {
        try Task.checkCancellation()
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values.isDirectory == true {
            let names = try Self.recursiveBasenames(in: url, limit: limits.maximumDocumentCount)
            try Task.checkCancellation()
            let kind: FoundryArtifactKind
            if names.contains("system.json") {
                kind = .systemPackage
            } else if names.contains("module.json") {
                kind = .modulePackage
            } else if names.contains("world.json") {
                kind = .worldPackage
            } else if names.contains(where: { $0.hasSuffix(".db") || $0.hasSuffix(".ldb") || $0.hasSuffix(".sst") }) {
                kind = .documentDatabase
            } else {
                kind = .unknown
            }
            return FoundryArtifact(kind: kind, suggestedName: url.lastPathComponent)
        }

        guard let fileSize = values.fileSize, fileSize <= limits.maximumArchiveSize else {
            throw FoundryImportError.fileTooLarge(values.fileSize ?? Int.max)
        }
        let lowercasedName = url.lastPathComponent.lowercased()
        if lowercasedName.hasSuffix(".dd2vtt") || lowercasedName.hasSuffix(".uvtt") {
            return FoundryArtifact(kind: .universalVTT, suggestedName: url.deletingPathExtension().lastPathComponent)
        }
        if lowercasedName.hasSuffix(".mrpgfoundry") {
            return FoundryArtifact(kind: .masterRPGBridge, suggestedName: url.deletingPathExtension().lastPathComponent)
        }
        if lowercasedName.hasSuffix(".db") || lowercasedName.hasSuffix(".ldb") || lowercasedName.hasSuffix(".sst") {
            return FoundryArtifact(kind: .documentDatabase, suggestedName: url.deletingPathExtension().lastPathComponent)
        }

        try Task.checkCancellation()
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        try Task.checkCancellation()
        if data.starts(with: [0x50, 0x4b, 0x03, 0x04]) || data.starts(with: [0x50, 0x4b, 0x05, 0x06]) {
            let archive = try FoundryZIPArchive(data: data, limits: limits)
            var basenames = Set<String>()
            for path in archive.entryPaths {
                try Task.checkCancellation()
                if let basename = path.split(separator: "/").last?.lowercased() {
                    basenames.insert(basename)
                }
            }
            let kind: FoundryArtifactKind
            if basenames.contains("system.json") {
                kind = .systemPackage
            } else if basenames.contains("module.json") {
                kind = .modulePackage
            } else if basenames.contains("world.json") {
                kind = .worldPackage
            } else {
                kind = .unknown
            }
            return FoundryArtifact(kind: kind, suggestedName: url.deletingPathExtension().lastPathComponent)
        }

        if Self.hasBridgeHeader(data, maximumLineSize: limits.maximumEntrySize) {
            return FoundryArtifact(kind: .masterRPGBridge, suggestedName: url.deletingPathExtension().lastPathComponent)
        }
        if lowercasedName == "system.json" {
            return FoundryArtifact(kind: .systemPackage, suggestedName: url.deletingPathExtension().lastPathComponent)
        }
        if lowercasedName == "module.json" {
            return FoundryArtifact(kind: .modulePackage, suggestedName: url.deletingPathExtension().lastPathComponent)
        }
        if lowercasedName == "world.json" {
            return FoundryArtifact(kind: .worldPackage, suggestedName: url.deletingPathExtension().lastPathComponent)
        }
        // Parsed once: the container check and the Universal VTT check used to parse the file twice.
        if lowercasedName.hasSuffix(".json"), let json = try? JSONSerialization.jsonObject(with: data),
           json is [String: Any] || json is [Any] {
            try Task.checkCancellation()
            let kind: FoundryArtifactKind = Self.looksLikeUniversalVTT(json) ? .universalVTT : .exportedDocument
            return FoundryArtifact(kind: kind, suggestedName: url.deletingPathExtension().lastPathComponent)
        }
        return FoundryArtifact(kind: .unknown, suggestedName: url.lastPathComponent)
    }
}

private extension FoundryArtifactDetector {
    static func hasBridgeHeader(_ data: Data, maximumLineSize: Int) -> Bool {
        guard maximumLineSize >= 0 else { return false }
        let (requestedInspectionCount, overflow) = maximumLineSize.addingReportingOverflow(1)
        let inspectionCount = min(data.count, overflow ? data.count : requestedInspectionCount)
        let prefix = data.prefix(inspectionCount)
        guard let newline = prefix.firstIndex(of: 0x0a) else { return false }
        let line = prefix[..<newline].trimmingASCIIWhitespace()
        guard line.count <= maximumLineSize else { return false }
        guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { return false }
        return object["record"] as? String == "manifest"
            && object["format"] as? String == "masterrpg-foundry-bridge"
    }

    static func looksLikeUniversalVTT(_ json: Any) -> Bool {
        guard let object = json as? [String: Any],
              object["image"] is String,
              let resolution = object["resolution"] as? [String: Any] else { return false }
        return resolution["map_size"] != nil && resolution["pixels_per_grid"] != nil
    }

    static func recursiveBasenames(in directory: URL, limit: Int) throws -> Set<String> {
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: Array(keys),
            options: [.skipsHiddenFiles, .skipsPackageDescendants]
        ) else { throw FoundryImportError.unsupportedSource }
        var names = Set<String>()
        var count = 0
        for case let fileUrl as URL in enumerator {
            try Task.checkCancellation()
            let values = try fileUrl.resourceValues(forKeys: keys)
            guard values.isSymbolicLink != true, values.isRegularFile == true else { continue }
            names.insert(fileUrl.lastPathComponent.lowercased())
            count += 1
            guard count <= limit else { throw FoundryImportError.tooManyDocuments(count) }
        }
        return names
    }
}

private extension Data.SubSequence {
    func trimmingASCIIWhitespace() -> Data {
        var start = startIndex
        var end = endIndex
        while start < end, self[start] == 0x20 || self[start] == 0x09 || self[start] == 0x0d {
            formIndex(after: &start)
        }
        while start < end {
            let before = index(before: end)
            guard self[before] == 0x20 || self[before] == 0x09 || self[before] == 0x0d else { break }
            end = before
        }
        return Data(self[start..<end])
    }
}
