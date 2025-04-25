// @copyright André Trettin

import Foundation

struct CloudDocumentController: Sendable {
    // e.g.: Pdf
    let modulePath: String

    private let cloudDocumentsHandler = CloudDocumentsHandler()

    func read(filePath: String) async throws -> Data? {
        try? await cloudDocumentsHandler.read(url: fileUrl(filePath: filePath))
    }

    func write(data: Data, to filePath: String) async throws {
        let parentDir = fileUrl(filePath: filePath).deletingLastPathComponent()
        try await FileManager.default.createDirectory(coordinatingAccessAt: parentDir, withIntermediateDirectories: true)
        try await cloudDocumentsHandler.write(targetURL: fileUrl(filePath: filePath), data: data)
    }

    func url(fileUrl: URL) -> URL {
        var nameUrl = moduleUrl
        let compPath = fileUrl.pathComponents
        compPath.forEach {
            nameUrl.append(path: $0)
        }
        return nameUrl
    }
    
    func createNameUrl(for selectedUrl: URL) async throws -> URL {
        if isCloud(url: selectedUrl) {
            return selectedUrl
        } else {
            let data = try await cloudDocumentsHandler.read(url: selectedUrl)
            let filename = selectedUrl.lastPathComponent
            let name = CloudDocumentController.suggestedFileName(for: modulePath, filename: filename, category: "New", tags: [])
            return fileUrl(filePath: name)
        }
    }

    func move(from fileUrl: FileUrl, sourceFilename: String, name: String, category: String, tags: [String]) async throws -> String? {
        var filename: String
        switch fileUrl.location {
            case .appCloud, .local:
                filename = name
            case .icloud, .other:
                filename = fileUrl.rawUrl.absoluteString
            case .newCloud, .url:
                return nil
        }
        var newName = CloudDocumentController.suggestedFileName(for: modulePath, filename: filename, category: category, tags: tags)
        let fileExtension = fileUrl.rawUrl.pathExtension
        newName = "\(newName).\(fileExtension)"
        let sourceUrl = URL(string: sourceFilename)!
        let data = try await cloudDocumentsHandler.read(url: sourceUrl)
        try await write(data: data, to: newName)
        
        return newName
    }

    func download(filePath: String) async throws {
        try await cloudDocumentsHandler.download(url: fileUrl(filePath: filePath))
    }
}

extension CloudDocumentController {
    static func suggestedFileName(for modulePath: String, filename: String, category: String, tags: [String]) -> String {
        "\(category)/\(filename)"
    }
}

private extension CloudDocumentController {
    func isCloud(url: URL) -> Bool {
        url.absoluteString.hasPrefix(moduleUrl.absoluteString)
    }
    
    func fileUrl(filePath: String) -> URL {
        moduleUrl.appending(path: filePath)
    }

    var moduleUrl: URL {
        let root = FileManager.cloudURL ?? FileManager.groupURL
        return root.appending(path: "Documents").appending(path: modulePath)
    }
}
