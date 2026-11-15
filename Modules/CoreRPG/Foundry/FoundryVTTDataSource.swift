// @copyright André Trettin

import Foundation

// MARK: - Data Source Abstraction (ZIP / Directory)

enum FoundryVTTDataSource: Sendable {
    case archive(FoundryZIPArchive, sourceSHA256: String)
    case directory(root: URL, paths: [String], pathSet: Set<String>, limits: FoundryImportLimits, selectedPath: String?)

    init(url: URL, limits: FoundryImportLimits) throws {
        let values = try url.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey])
        if values.isDirectory == true {
            let root = url.standardizedFileURL.resolvingSymlinksInPath()
            let paths = try Self.directoryPaths(at: root, limits: limits).sorted()
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
        if FoundryPackagePath.isManifest(lowercased) {
            throw FoundryImportError.bareManifestRequiresContainer(url.lastPathComponent)
        }
        let isPlainFile = lowercased.hasSuffix(".json")
            || lowercased.hasSuffix(".db")
            || lowercased.hasSuffix(".ldb")
            || lowercased.hasSuffix(".sst")
            || lowercased.hasSuffix(".mrpgfoundry")
        if isPlainFile {
            let root = url.deletingLastPathComponent().standardizedFileURL.resolvingSymlinksInPath()
            let selected = try FoundryPackagePath.normalized(url.lastPathComponent)
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
            let stamp = FoundryZIPArchive.SourceStamp(url: url)
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            try Task.checkCancellation()
            self = .archive(
                try FoundryZIPArchive(data: data, limits: limits, sourceStamp: stamp),
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

    /// The paths under `prefix` (all of them for an empty prefix), found by binary search in a
    /// sorted list instead of by filtering every path for every collection. A crafted archive
    /// with tens of thousands of directories used to cost collections x paths. The caller still
    /// tests each result, so an unusual Unicode ordering can only make the slice larger, never
    /// wrong. See CODE_AUDIT_26 §7.2.
    func paths(withPrefix prefix: String) -> [String] {
        switch self {
        case .archive(let archive, _): archive.paths(withPrefix: prefix)
        case .directory(_, let paths, _, _, _): FoundryPathSearch.paths(withPrefix: prefix, inSorted: paths)
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
            let rootPath = root.path(percentEncoded: false)
            let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
            guard candidate.path(percentEncoded: false).hasPrefix(rootPrefix) else {
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
        let rootPath = canonicalRoot.path(percentEncoded: false)
        let rootPrefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
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
            let canonicalPath = canonical.path(percentEncoded: false)
            guard canonicalPath.hasPrefix(rootPrefix) else {
                throw FoundryImportError.invalidArchive("A package path escapes its selected directory.")
            }
            result.append(try FoundryPackagePath.normalized(String(canonicalPath.dropFirst(rootPrefix.count))))
            guard result.count <= limits.maximumDocumentCount else {
                throw FoundryImportError.tooManyDocuments(result.count)
            }
        }
        return result.sorted()
    }
}



/// Prefix lookup in a sorted path list.
enum FoundryPathSearch {
    static func paths(withPrefix prefix: String, inSorted sorted: [String]) -> [String] {
        guard !prefix.isEmpty else { return sorted }
        var low = 0
        var high = sorted.count
        while low < high {
            let middle = (low + high) / 2
            if sorted[middle] < prefix { low = middle + 1 } else { high = middle }
        }
        var result: [String] = []
        var index = low
        while index < sorted.count, sorted[index].hasPrefix(prefix) {
            result.append(sorted[index])
            index += 1
        }
        return result
    }
}
