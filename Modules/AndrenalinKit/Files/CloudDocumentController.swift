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

    func move(from fileUrl: FileUrl, sourceFilename: String, name: String, category: String, tags: [String]) async throws -> String? {
        var filename: String?
        switch fileUrl.location {
            case .appCloud, .local:
                filename = nil
            case .icloud, .other:
                filename = fileUrl.rawUrl.absoluteString
            case .newCloud, .url:
                return nil
        }
        var newName = CloudDocumentController.suggestedFileName(for: modulePath, filename: filename, name: name, category: category, tags: tags)
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
    static func suggestedFileName(for modulePath: String, filename: String?, name: String, category: String, tags: [String]) -> String {

        if let filename {
            return filename
        }
        return "\(category)/\(name)"
    }
}

private extension CloudDocumentController {
    func fileUrl(filePath: String) -> URL {
        moduleUrl.appending(path: filePath)
    }

    var moduleUrl: URL {
        let root = FileManager.cloudURL ?? FileManager.groupURL
        return root.appending(path: "Documents").appending(path: modulePath)
    }
}
