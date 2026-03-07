// @copyright André Trettin

import Foundation

struct CloudDocumentController: Sendable {
    init(modulePath: String) {
        self.modulePath = modulePath[modulePath.startIndex..<modulePath.index(before: modulePath.endIndex)].lowercased()
    }
    
    // e.g.: Pdf
    let modulePath: String

    func fullUrl(fileUrl: URL) -> URL {
        var nameUrl = moduleUrl
        let compPath = fileUrl.pathComponents
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
        try? await FileManager.default.contentsOfFile(coordinatingAccessAt: fullUrl(filePath: filePath))
    }

    func write(data: Data, to filePath: String) async throws {
        let parentDir = fullUrl(filePath: filePath).deletingLastPathComponent()
        try await FileManager.default.createDirectory(coordinatingAccessAt: parentDir, withIntermediateDirectories: true)
        try await FileManager.default.write(data, coordinatingAccessTo: fullUrl(filePath: filePath))
    }

    func download(filePath: String) async throws {
        try await FileManager.default.download(coordinatingAccessAt: fullUrl(filePath: filePath))
    }

    func createNameUrl(for selectedUrl: URL, category: String) async throws -> URL {
        if isCloud(url: selectedUrl) {
            return selectedUrl
        } else {
            let filename = selectedUrl.lastPathComponent
            let name = CloudDocumentController.suggestedFileName(for: modulePath, filename: filename, category: category)
            let newFilename = try await move(sourceUrl: selectedUrl, destinationFilename: name)
            return fullUrl(filePath: newFilename)
        }
    }

    func move(sourceUrl: URL, destinationFilename: String) async throws -> String {
        let data = try await FileManager.default.contentsOfFile(coordinatingAccessAt: sourceUrl)
        try await write(data: data, to: destinationFilename)
        return destinationFilename
    }

    func move(url: URL, newCategory destination: String) async throws -> (URL, URL)? {
        var pathComponents = url.pathComponents
        guard let filename = pathComponents.last, pathComponents.count > 1 else { return nil }
        pathComponents[0] = destination
        let path = pathComponents.dropLast().joined(separator: "/")
        let newFilename = try await suggestedFileName(for: path, filename: filename)
        let newPath = path.appending("/\(newFilename)")
        let destinationDirUrl = fullUrl(filePath: path)
        try await FileManager.default.createDirectory(coordinatingAccessAt: destinationDirUrl, withIntermediateDirectories: true)
        try await FileManager.default.moveItem(coordinatingAccessFrom: fullUrl(fileUrl: url), to: fullUrl(filePath: newPath))
        guard let relativeUrl = URL(string: newPath) else { return nil }
        return (fullUrl(filePath: newPath), relativeUrl)
    }

    func move(url: URL, newName destination: String) async throws -> (URL, URL)? {
        guard let newUrl = URL(string: destination) else { return nil }
        let pathComponents = newUrl.pathComponents
        guard pathComponents.last != nil else { return nil }
        
        let fileExt = url.pathExtension
        let path = pathComponents.dropLast().joined(separator: "/")
        let filename = newUrl.lastPathComponent + ".\(fileExt)"
        
        let newFilename = try await suggestedFileName(for: path, filename: filename)
        let newPath = path.appending("\(path.isEmpty ? "" : "/")" + newFilename)
        let destinationDirUrl = fullUrl(filePath: path)
        _ = destinationDirUrl.startAccessingSecurityScopedResource()
        defer { destinationDirUrl.stopAccessingSecurityScopedResource() }
        try await FileManager.default.createDirectory(coordinatingAccessAt: destinationDirUrl, withIntermediateDirectories: true)
        try await FileManager.default.moveItem(coordinatingAccessFrom: fullUrl(fileUrl: url), to: fullUrl(filePath: newPath))
        guard let relativeUrl = URL(string: newPath) else { return nil }
        return (fullUrl(filePath: newPath), relativeUrl)
    }
}

extension CloudDocumentController {
    static func suggestedFileName(for modulePath: String, filename: String, category: String) -> String {
        "\(category)/\(filename)"
    }
    
    func suggestedFileName(for path: String, filename: String) async throws -> String {
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
