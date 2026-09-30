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
        self.modulePath = modulePath[modulePath.startIndex..<modulePath.index(before: modulePath.endIndex)].lowercased()
    }
    
    // e.g.: Pdf
    let modulePath: String

    func fullUrl(fileUrl: URL) -> URL {
        var nameUrl = moduleUrl
        // An absolute url (imported from another device or a legacy item) must be
        // reduced to its name below Documents/<module> — appending it verbatim
        // produces .../<module>/Users/... which never exists on this device.
        let components = fileUrl.pathComponents
        let compPath: [String]
        if components.contains(CloudDocumentController.documentDirName) {
            compPath = Array(components.drop(while: { $0 != CloudDocumentController.documentDirName }).dropFirst(2))
        } else {
            compPath = components.filter { $0 != "/" }
        }
        // `FileUrl`s arrive from imported files and game peers, so `..` segments must never
        // be able to climb out of `Documents/<module>`. See CODE_AUDIT_15 §5.1.
        CloudDocumentController.safeComponents(compPath).forEach {
            nameUrl.append(path: $0)
        }
        return nameUrl
    }

    func fullUrl(filePath: String) -> URL {
        var url = moduleUrl
        CloudDocumentController.safeComponents(filePath.split(separator: "/").map(String.init)).forEach {
            url.append(path: $0)
        }
        return url
    }

    func nameUrl(fullUrl: URL) -> URL {
        let namePath = fullUrl.pathComponents.drop(while: { $0 != CloudDocumentController.documentDirName }).dropFirst(2)
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
        
        let fileUrl = fullUrl(filePath: filePath)
        // Batch both operations into single coordinated access
        try await FileManager.default.updateFile(coordinatingAccessTo: fileUrl) { url in
            let parentDir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try data.write(to: url)
        }
    }

    func download(filePath: String) async throws {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.download(filePath:)", file: "CloudDocumentController.swift")
        
        try await FileManager.default.download(coordinatingAccessAt: fullUrl(filePath: filePath))
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
            let name = try await suggestedFileName(for: "", filename: filename)
            let newFilename = try await move(sourceUrl: selectedUrl, destinationFilename: name)
            return fullUrl(filePath: newFilename)
        }
    }

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
        try await FileManager.default.copyReplacingItem(coordinatingAccessFrom: sourceUrl, to: fullUrl(filePath: filePath))
    }

    func move(url: URL, newCategory destination: String) async throws -> (URL, URL)? {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.move(url:newCategory:)", file: "CloudDocumentController.swift")
        
        var pathComponents = url.pathComponents
        guard let filename = pathComponents.last, pathComponents.count > 1 else { return nil }
        pathComponents[0] = destination
        let path = pathComponents.dropLast().joined(separator: "/")
        let newFilename = try await suggestedFileName(for: path, filename: filename)
        let newPath = path.appending("/\(newFilename)")
        
        let sourceUrl = fullUrl(fileUrl: url)
        let destUrl = fullUrl(filePath: newPath)
        
        // Batch directory creation and move into the move operation's coordination
        try await FileManager.default.updateFile(coordinatingAccessTo: destUrl) { coordDestUrl in
            let parentDir = coordDestUrl.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: sourceUrl, to: coordDestUrl)
        }
        
        guard let relativeUrl = URL(string: newPath) else { return nil }
        return (destUrl, relativeUrl)
    }

    func move(url: URL, newName destination: String) async throws -> (URL, URL)? {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.move(url:newName:)", file: "CloudDocumentController.swift")
        
        guard let newUrl = URL(string: destination) else { return nil }
        let pathComponents = newUrl.pathComponents
        guard pathComponents.last != nil else { return nil }
        
        let fileExt = url.pathExtension
        let path = pathComponents.dropLast().joined(separator: "/")
        let filename = newUrl.lastPathComponent + ".\(fileExt)"
        
        guard destination + ".\(fileExt)" != url.path(percentEncoded: false) else { return nil }
        let newFilename = try await suggestedFileName(for: path, filename: filename)
        let newPath = path.appending("\(path.isEmpty ? "" : "/")" + newFilename)
        
        let sourceUrl = fullUrl(fileUrl: url)
        let destUrl = fullUrl(filePath: newPath)
        
        // Batch directory creation and move into single coordinated operation
        try await FileManager.default.updateFile(coordinatingAccessTo: destUrl) { coordDestUrl in
            let parentDir = coordDestUrl.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)
            try FileManager.default.moveItem(at: sourceUrl, to: coordDestUrl)
        }
        
        guard let relativeUrl = URL(string: newPath) else { return nil }
        return (destUrl, relativeUrl)
    }
}

extension CloudDocumentController {
    static func suggestedFileName(for modulePath: String, filename: String, category: String) -> String {
        "\(category)/\(filename)"
    }
    
    func suggestedFileName(for path: String, filename: String) async throws -> String {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.suggestedFileName(for:filename:)", file: "CloudDocumentController.swift")
        
        let url = fullUrl(filePath: path + "/" + filename)
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
            if let extractedNumber = Int(numbers[numCounter - 1]) {
                number = extractedNumber + 1
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
    static func safeComponents(_ components: [String]) -> [String] {
        components.filter { !$0.isEmpty && $0 != "/" && $0 != "." && $0 != ".." }
    }

    /// Whether `url` contains a segment `safeComponents(_:)` would drop as a traversal.
    static func hasTraversalComponents(_ url: URL) -> Bool {
        url.pathComponents.contains { $0 == ".." || $0 == "." }
    }
}

extension CloudDocumentController {
    /// The canonical "Documents" path component every module-relative cloud/local
    /// file root is built under. Shared module-wide so it's declared exactly
    /// once instead of re-hardcoded as a literal at each call site.
    static let documentDirName: String = "Documents"
}

private extension CloudDocumentController {
    func isCloud(url: URL) -> Bool {
        url.absoluteString.hasPrefix(moduleUrl.absoluteString)
    }

    var moduleUrl: URL {
        let root = FileManager.preferredRootUrl
        return root.appending(path: CloudDocumentController.documentDirName).appending(path: modulePath)
    }
}
