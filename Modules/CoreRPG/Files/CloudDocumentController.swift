// @copyright André Trettin

import Foundation
import os.log

// MARK: - CloudKit Operation Counter

// Actually enforces something (a periodic reset + a one-time-per-window log warning) instead
// of being pure write-only telemetry nobody ever read or reset — see
// CODE_AUDIT §9.2. `warningThreshold` is a heuristic, not an Apple-documented CloudKit quota:
// it exists to surface an unusually chatty day of Core Data saves/file operations in the log
// before they risk CloudKit's actual per-request rate limits, not to enforce a real limit.
actor CloudKitOperationCounter {
    static let shared = CloudKitOperationCounter()

    private static let warningThreshold = 1_000
    private static let resetInterval: Duration = .seconds(24 * 60 * 60)

    private var operationCount = 0
    private var startTime = Date()
    private var hasWarnedThisWindow = false
    private var resetTask: Task<Void, Never>?

    init() {
        // Reached via `Self.shared`/`CloudKitOperationCounter.shared`, not a `self` capture:
        // an actor's synchronous init only permits nonisolated access to `self` once a closure
        // in its body has captured `self` for later (Sendable/escaping) use, so this task
        // deliberately avoids capturing `self` at all — it only reaches back into the actor
        // once the singleton is fully constructed, when the task actually runs.
        resetTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.resetInterval)
                await CloudKitOperationCounter.shared.reset()
            }
        }
    }

    deinit {
        resetTask?.cancel()
    }

    func recordOperation(function: String, file: String) {
        operationCount += 1
        let elapsed = Date().timeIntervalSince(startTime)
        Logger.fileStore.info("☁️ CloudKit Op #\(self.operationCount, privacy: .public) [\(elapsed, privacy: .public)s] - \(function, privacy: .public)")

        guard operationCount >= Self.warningThreshold, !hasWarnedThisWindow else { return }
        hasWarnedThisWindow = true
        Logger.fileStore.warning("☁️ CloudKit operation count has crossed \(Self.warningThreshold, privacy: .public) since \(self.startTime, privacy: .public) — check for a sync loop or an unusually chatty batch.")
    }

    func reset() {
        operationCount = 0
        startTime = Date()
        hasWarnedThisWindow = false
    }
}

struct CloudDocumentController: Sendable {
    init(modulePath: String) {
        // Without the plural "s"; `dropLast()` leaves an empty name empty instead of trapping.
        self.modulePath = modulePath.dropLast().lowercased()
    }
    
    // e.g.: Pdf
    let modulePath: String

    /// Where the stored path `fileUrl` is on this device, or `nil` when it names no file below the
    /// module folder.
    ///
    /// A stored path is relative and is taken as it is: a user folder may be called "Documents".
    /// Stripping everything up to a `Documents` component by name resolved `Documents/Rules.pdf`
    /// to the module folder itself, and a delete of that item then removed every file of the
    /// module. Only an absolute file url (a legacy item, or one from another device) carries a
    /// container prefix, and only that is reduced. See CODE_AUDIT_21 §5.1, §6.1.
    func fullUrl(fileUrl: URL) -> URL? {
        let components: [String]
        if fileUrl.isFileURL, let belowContainer = componentsBelowContainer(of: fileUrl) {
            components = belowContainer
        } else {
            components = fileUrl.pathComponents
        }
        return moduleFileUrl(components)
    }

    /// `filePath` below the module folder, or `nil` when it names no file there.
    func fullUrl(filePath: String) -> URL? {
        moduleFileUrl(filePath.split(separator: "/").map(String.init))
    }

    /// The path of the stored file `fileUrl` below the module folder, or `nil` when it names no
    /// file there.
    func relativeComponents(of fileUrl: URL) -> [String]? {
        fullUrl(fileUrl: fileUrl).flatMap { componentsBelowContainer(of: $0) }
    }

    func nameUrl(fullUrl: URL) -> URL {
        let namePath = componentsBelowContainer(of: fullUrl) ?? []
        // `pathComponents` yields already-decoded segments, which can contain characters
        // invalid in a URL string (`#`, unencoded `%`/`?`, ...); build from a clean base
        // and append via `.append(path:)`, which percent-encodes each component, instead
        // of round-tripping the first segment through `URL(string:)!`.
        var name = URL(string: "/")!
        if let first = namePath.first {
            name.append(path: first)
        }
        namePath.dropFirst().forEach {
            name.append(path: $0)
        }
        return name
    }
    
    func write(data: Data, to filePath: String) async throws {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.write(data:to:)", file: "CloudDocumentController.swift")
        
        let fileUrl = try destinationUrl(filePath: filePath)
        // Batch both operations into single coordinated access
        try await FileManager.default.updateFile(coordinatingAccessTo: fileUrl) { url in
            let parentDir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            // Atomic: a failed replacement in place used to leave the old file truncated.
            // See CODE_AUDIT_21 §5.2.
            try data.write(to: url, options: .atomic)
        }
    }

    func download(filePath: String) async throws {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.download(filePath:)", file: "CloudDocumentController.swift")
        
        try await FileManager.default.download(coordinatingAccessAt: destinationUrl(filePath: filePath))
    }

    func createNameUrl(for selectedUrl: URL) async throws -> URL {
        if isCloud(url: selectedUrl) {
            return selectedUrl
        } else {
            let filename = selectedUrl.lastPathComponent
            // Two picked files sharing a bare name (two `map.png` picks) would
            // otherwise collide on the same destination path: the second write
            // silently overwrites the first item's bytes, and deleting either item
            // then deletes the file for both. Dedupe against the destination root
            // the same way the sibling `move(url:newCategory:)`/`move(url:newName:)`
            // already do. See CODE_AUDIT_17 §5.4.
            //
            // The free name is only a suggestion: another import can take it before the copy
            // lands, so the copy never replaces and the next name is tried when it loses the race.
            // See CODE_AUDIT §5.1.
            await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.createNameUrl(for:)", file: "CloudDocumentController.swift")
            var name = try await suggestedFileName(for: "", filename: filename)
            for attempt in 1...Self.maximumCopyNameAttempts {
                do {
                    try await copyWithoutReplacing(from: selectedUrl, to: name)
                    return try destinationUrl(filePath: name)
                } catch let error as CocoaError where error.code == .fileWriteFileExists && attempt < Self.maximumCopyNameAttempts {
                    name = try await suggestedFileName(for: "", filename: Self.increasedFileName(for: name))
                }
            }
            throw CocoaError(.fileWriteFileExists)
        }
    }

    /// Every lost race moves on to a free name, so as many equally named picks at once as there
    /// are attempts all get one.
    private static let maximumCopyNameAttempts = 50

    /// Copies the picked file file-to-file: reading it into memory first spiked memory for
    /// large audio, USDZ or PDF files. See CODE_AUDIT_19 §7.1.
    func move(sourceUrl: URL, destinationFilename: String) async throws -> String {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.move(sourceUrl:destinationFilename:)", file: "CloudDocumentController.swift")
        
        try await copy(from: sourceUrl, to: destinationFilename)
        return destinationFilename
    }

    /// Copies `sourceUrl` to `filePath` below the module folder without reading it into memory.
    /// See CODE_AUDIT_19 §7.1.
    func copy(from sourceUrl: URL, to filePath: String) async throws {
        try await FileManager.default.copyReplacingItem(coordinatingAccessFrom: sourceUrl, to: destinationUrl(filePath: filePath))
    }

    /// Like `copy(from:to:)`, but throws `fileWriteFileExists` when `filePath` is already taken
    /// instead of replacing that file. See CODE_AUDIT_Folder §3.18.
    func copyWithoutReplacing(from sourceUrl: URL, to filePath: String) async throws {
        try await FileManager.default.copyItemWithoutReplacing(coordinatingAccessFrom: sourceUrl, to: destinationUrl(filePath: filePath))
    }

    func move(url: URL, newCategory destination: String) async throws -> (URL, URL)? {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.move(url:newCategory:)", file: "CloudDocumentController.swift")
        
        var pathComponents = url.pathComponents
        guard let filename = pathComponents.last, pathComponents.count > 1 else { return nil }
        pathComponents[0] = destination
        let path = pathComponents.dropLast().joined(separator: "/")
        let newFilename = try await suggestedFileName(for: path, filename: filename)
        let newPath = path.appending("/\(newFilename)")
        
        guard let sourceUrl = fullUrl(fileUrl: url) else { return nil }
        let destUrl = try destinationUrl(filePath: newPath)
        
        // Directory creation and move in one coordinated write of source and destination: the
        // source is also an iCloud file other processes may touch. See CODE_AUDIT §5.2.
        try await FileManager.default.moveItem(coordinatingAccessFrom: sourceUrl, to: destUrl, createParentFolder: true)
        
        guard let relativeUrl = URL(string: newPath) else { return nil }
        return (destUrl, relativeUrl)
    }

    func move(url: URL, newName destination: String) async throws -> (URL, URL)? {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.move(url:newName:)", file: "CloudDocumentController.swift")
        
        // The folder and item names, split by hand. Parsed with `URL(string:)`, a `#` or `?` in a
        // name cut the path there and `%41` was decoded, so the file got a wrong name or
        // landed at the module root. See CODE_AUDIT_21 §5.15.
        let names = destination.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard let name = names.last else { return nil }

        let fileExt = url.pathExtension
        let path = names.dropLast().joined(separator: "/")
        let filename = fileExt.isEmpty ? name : name + ".\(fileExt)"

        guard let sourceUrl = fullUrl(fileUrl: url) else { return nil }
        // Already there: compared as resolved locations. The text comparison never matched (the
        // stored path has a leading slash, the destination none), so the file collided with
        // itself and was renamed `name-1` on every call. See CODE_AUDIT_21 §5.15.
        let requestedPath = path.isEmpty ? filename : path + "/" + filename
        if let requestedUrl = fullUrl(filePath: requestedPath),
           CloudDocumentController.canonicalPath(requestedUrl) == CloudDocumentController.canonicalPath(sourceUrl) {
            return nil
        }
        let newFilename = try await suggestedFileName(for: path, filename: filename)
        let newPath = path.isEmpty ? newFilename : path + "/" + newFilename

        let destUrl = try destinationUrl(filePath: newPath)
        
        // Directory creation and move in one coordinated write of source and destination: the
        // source is also an iCloud file other processes may touch. See CODE_AUDIT §5.2.
        try await FileManager.default.moveItem(coordinatingAccessFrom: sourceUrl, to: destUrl, createParentFolder: true)

        // Built per component, like every other stored path: each name is percent-encoded.
        return (destUrl, nameUrl(fullUrl: destUrl))
    }
}

extension CloudDocumentController {
    static func suggestedFileName(for modulePath: String, filename: String, category: String) -> String {
        "\(category)/\(filename)"
    }
    
    func suggestedFileName(for path: String, filename: String) async throws -> String {
        let url = try destinationUrl(filePath: path + "/" + filename)
        let (exists, _) = try await FileManager.default.fileExists(coordinatingAccessAt: url)
        if exists {
            let newFilename = CloudDocumentController.increasedFileName(for: filename)
            return try await suggestedFileName(for: path, filename: newFilename)
        }
        return filename
    }

    static func increasedFileName(for filename: String) -> String {
        let comp = filename.split(separator: ".", omittingEmptySubsequences: false)
        let count = comp.count
        let ext: String
        let name: String
        if count > 1 {
            ext = "." + String(comp[count - 1])
            name = String(comp.dropLast().joined(separator: "."))
        } else {
            ext = ""
            name = String(comp.joined(separator: "."))
        }
        let numbers = name.split(separator: "-", omittingEmptySubsequences: false)
        let numCounter = numbers.count
        let number: Int
        var newFilename: String
        if numCounter > 1 {
            // A counter at `Int.max` (a crafted import name) is kept as part of the name: adding
            // one to it trapped. See CODE_AUDIT_21 §6.4.
            let next = Int(numbers[numCounter - 1]).map { $0.addingReportingOverflow(1) }
            if let next, !next.overflow {
                number = next.partialValue
                newFilename = numbers.dropLast().joined(separator: "-")
            } else {
                number = 1
                newFilename = numbers.joined(separator: "-")
            }
        } else {
            number = 1
            newFilename = numbers.joined(separator: "-")
        }
        newFilename.append("-\(number)\(ext)")
        return newFilename
    }
}

extension CloudDocumentController {
    /// Drops the segments that would let a path leave the directory it is appended to
    /// (`..`, `.`) together with empty and root segments. Every builder that turns a
    /// decoded `FileUrl` path into a file-system URL goes through this.
    /// See CODE_AUDIT_15 §5.1.
    ///
    /// A component is split at `/` first: `pathComponents` decodes `..%2F..%2Fx` into the
    /// single component `../../x`, which passed the filter and was split again by
    /// `append(path:)`, so the file resolved outside the module folder. See CODE_AUDIT_Folder §6.3.
    static func safeComponents(_ components: [String]) -> [String] {
        components
            .flatMap { $0.split(separator: "/", omittingEmptySubsequences: true).map(String.init) }
            .filter { $0 != "." && $0 != ".." }
    }

    /// Whether `url` contains a segment `safeComponents(_:)` would drop or split as a traversal.
    static func hasTraversalComponents(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".." || $0 == "." || ($0 != "/" && $0.contains("/")) }
    }

    /// Whether `url` lies inside `root` once `.` and `..` are resolved.
    ///
    /// Compared as written, without the file system: `standardizedFileURL` drops a leading
    /// `/private` only when the shortened path exists. On a device (containers are below
    /// `/private/var`) a file about to be written kept `/private` while its existing folder
    /// lost it, so every new file compared as outside its own module folder and could not be
    /// stored.
    static func isContained(_ url: URL, in root: URL) -> Bool {
        let rootPath = root.standardized.path(percentEncoded: false)
        let path = url.standardized.path(percentEncoded: false)
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        return path == rootPath || path.hasPrefix(prefix)
    }

    /// The path of `url` with `.`/`..` removed and the symlinks of its existing part resolved.
    /// The same whether the file itself exists or not (see `isContained(_:in:)`), so the path
    /// of a file that is still to be written can be compared with the path of an existing one.
    static func canonicalPath(_ url: URL) -> String {
        var existing = url.standardizedFileURL
        var missing: [String] = []
        while existing.pathComponents.count > 1,
              !FileManager.default.fileExists(atPath: existing.path(percentEncoded: false)) {
            missing.append(existing.lastPathComponent)
            existing.deleteLastPathComponent()
        }
        var path = existing.resolvingSymlinksInPath().path(percentEncoded: false)
        while path.count > 1, path.hasSuffix("/") {
            path.removeLast()
        }
        return missing.reversed().reduce(into: path) { path, component in
            path += (path.hasSuffix("/") ? "" : "/") + component
        }
    }
}

extension CloudDocumentController {
    /// The canonical "Documents" path component every module-relative cloud/local
    /// file root is built under. Shared module-wide so it's declared exactly
    /// once instead of re-hardcoded as a literal at each call site.
    static let documentDirName: String = "Documents"
}

extension CloudDocumentController {
    /// The folder every file of this module is stored below.
    var moduleUrl: URL {
        let root = FileManager.preferredRootUrl
        return root.appending(path: CloudDocumentController.documentDirName).appending(path: modulePath)
    }
}

private extension CloudDocumentController {
    func isCloud(url: URL) -> Bool {
        CloudDocumentController.isContained(url, in: moduleUrl)
    }

    /// `components` below the module folder. `nil` when nothing is left once `.`, `..` and empty
    /// segments are dropped, or when the result is not inside the module folder: a resolver
    /// that answered with the module folder itself turned a later delete into a delete of the
    /// whole module. See CODE_AUDIT_15 §5.1, CODE_AUDIT_Folder §6.3, CODE_AUDIT_21 §5.1, §6.1.
    func moduleFileUrl(_ components: [String]) -> URL? {
        let safe = CloudDocumentController.safeComponents(components)
        guard !safe.isEmpty else { return nil }
        var url = moduleUrl
        safe.forEach { url.append(path: $0) }
        guard CloudDocumentController.isContained(url, in: moduleUrl) else { return nil }
        return url
    }

    /// `fullUrl(filePath:)` for a path that is written to or read from; a path that names no file
    /// below the module folder throws.
    func destinationUrl(filePath: String) throws -> URL {
        guard let url = fullUrl(filePath: filePath) else { throw CocoaError(.fileWriteInvalidFileName) }
        return url
    }

    /// The components of the absolute `url` below its `…/Documents/<module>/` container, or `nil`
    /// when it has none. This device's module folder is matched by its exact path; a container
    /// of another device is recognised by the first `Documents` component.
    func componentsBelowContainer(of url: URL) -> [String]? {
        let moduleComponents = CloudDocumentController.canonicalPath(moduleUrl).split(separator: "/")
        let absoluteComponents = CloudDocumentController.canonicalPath(url).split(separator: "/")
        if absoluteComponents.starts(with: moduleComponents) {
            return absoluteComponents.dropFirst(moduleComponents.count).map(String.init)
        }
        let components = url.pathComponents
        guard let index = components.firstIndex(of: CloudDocumentController.documentDirName) else { return nil }
        return Array(components.dropFirst(index + 2))
    }
}
