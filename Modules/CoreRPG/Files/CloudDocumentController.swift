// @copyright André Trettin

import Foundation
import os.log

// MARK: - CloudKit Operation Counter

actor CloudKitOperationCounter {
    static let shared = CloudKitOperationCounter()
    
    private var operationCount: Int = 0
    private let startTime: Date = Date()
    
    func recordOperation(function: String, file: String) {
        operationCount += 1
        let elapsed = Date().timeIntervalSince(startTime)
        Logger.fileStore.info("☁️ CloudKit Op #\(self.operationCount, privacy: .public) [\(elapsed, privacy: .public)s] - \(function, privacy: .public)")
    }
    
    func getCount() -> Int {
        return operationCount
    }
    
    func reset() {
        operationCount = 0
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
        compPath.forEach {
            nameUrl.append(path: $0)
        }
        return nameUrl
    }

    func fullUrl(filePath: String) -> URL {
        moduleUrl.appending(path: filePath)
    }

    func nameUrl(fullUrl: URL) -> URL {
        let namePath = fullUrl.pathComponents.drop(while: { $0 != CloudDocumentController.documentDirName }).dropFirst(2)
        var name = URL(string: namePath.first ?? "/")!
        namePath.dropFirst().forEach {
            name.append(path: $0)
        }
        return name
    }
    
    func read(filePath: String) async throws -> Data? {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.read(filePath:)", file: "CloudDocumentController.swift")
        
        let url = fullUrl(filePath: filePath)
        
        // Batch download check and read into single coordinated access
        return try await FileManager.default.updateFile(coordinatingAccessTo: url) { coordUrl in
            // Check if file needs to be downloaded first
            if let values = try? coordUrl.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey]),
               values.ubiquitousItemDownloadingStatus != .current {
                try? FileManager.default.startDownloadingUbiquitousItem(at: coordUrl)
                // Note: This starts async download, but doesn't wait for completion
            }
            
            return try Data(contentsOf: coordUrl)
        }
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
            let name = filename
            let newFilename = try await move(sourceUrl: selectedUrl, destinationFilename: name)
            return fullUrl(filePath: newFilename)
        }
    }

    func move(sourceUrl: URL, destinationFilename: String) async throws -> String {
        await CloudKitOperationCounter.shared.recordOperation(function: "CloudDocumentController.move(sourceUrl:destinationFilename:)", file: "CloudDocumentController.swift")
        
        let data = try await FileManager.default.contentsOfFile(coordinatingAccessAt: sourceUrl)
        try await write(data: data, to: destinationFilename)
        return destinationFilename
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

private extension CloudDocumentController {
    static let documentDirName: String = "Documents"

    func isCloud(url: URL) -> Bool {
        url.absoluteString.hasPrefix(moduleUrl.absoluteString)
    }
    
    var moduleUrl: URL {
        let root = FileManager.cloudURL ?? FileManager.groupURL
        return root.appending(path: CloudDocumentController.documentDirName).appending(path: modulePath)
    }
}
