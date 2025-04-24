// @copyright André Trettin

import Foundation

public struct LocationFileManager: Sendable {
    let rootAppCloud: URL?
    let rootLocal: URL?
    let rootICloud: URL?
    let rootNewCloud: URL
    let moduleFolder: String

    public init(moduleFolder: String) {
        self.moduleFolder = moduleFolder
        let cloud = FileManager.cloudURL
        self.rootAppCloud = cloud?.appendingPathComponent("Documents")
        self.rootICloud = cloud?.deletingLastPathComponent().appendingPathComponent("com~apple~CloudDocs/")
        self.rootLocal = URL.documentsDirectory
        self.rootNewCloud = (FileManager.cloudURL ?? FileManager.groupURL).appending(path: "Documents")
    }
}

public extension LocationFileManager {
    /// This function cannot detect iCloud nor AppCloud if the device has not enabled iCloud
    /// It will return then `other` as file location even the url might be iCloud nor AppCloud
    func fileLocation(for url: URL?) -> FileLocation? {
        guard let url else { return nil }
        let path = url.absoluteString
        if let rootAppCloud, path.starts(with: rootAppCloud.absoluteString) {
            return .appCloud
        }
        if let rootLocal, path.starts(with: rootLocal.absoluteString) {
            return .local
        }
        if let rootICloud, path.starts(with: rootICloud.absoluteString) {
            return .icloud
        }
        return .newCloud
    }

    func relativeUrl(for url: URL?) -> URL? {
        guard let url, let location = fileLocation(for: url) else { return url }
        switch location {
        case .appCloud:
            guard let cloudPath = rootAppCloud else { return url }
            return URL(string: url.absoluteString.replacingOccurrences(of: cloudPath.absoluteString, with: ""))
        case .icloud:
            guard let cloudPath = rootICloud else { return url }
            return URL(string: url.absoluteString.replacingOccurrences(of: cloudPath.absoluteString, with: ""))
        default:
            return url
        }
    }

    func absoluteUrl(for url: URL?, at location: FileLocation) -> URL? {
        guard let url else { return url }
        switch location {
        case .appCloud:
            guard let cloudPath = rootAppCloud else { return nil }
            return add(relative: url, to: cloudPath)
        case .icloud:
            guard let cloudPath = rootICloud else { return nil }
            return add(relative: url, to: cloudPath)
        case .newCloud:
            return add(relative: url, to: rootNewCloud)
        default:
            return url
        }
    }

    func copy(pickedURL: URL, to location: FileLocation, id: UUID) async throws -> URL? {
        guard let destinationURL = try await url(id: id, location: location, pathExtension: pickedURL.pathExtension, cloudUrl: nil) else { return nil }
        return try await copy(pickedURL: pickedURL, to: destinationURL)
    }

    func copy(pickedURL: URL, to newUrl: URL) async throws -> URL? {
        let destinationURL = newUrl
        let (exists, isDir) = try await FileManager.default.fileExists(coordinatingAccessAt: destinationURL)
        if exists && isDir == false {
            try await FileManager.default.removeItem(coordinatingAccessAt: destinationURL)
        }
        guard isDir == false else { return nil }
        try await FileManager.default.copyItem(coordinatingAccessFrom: pickedURL, to: destinationURL)
        return destinationURL
    }

    func create(id: UUID, location: FileLocation, pathExtension: String, data: Data, cloudUrl: URL? = nil) async throws -> URL? {
        guard let url = try await url(id: id, location: location, pathExtension: pathExtension, cloudUrl: cloudUrl) else { return nil }
        let (exists, _) = try await FileManager.default.fileExists(coordinatingAccessAt: url)
        if !exists {
            try await FileManager.default.write(data, coordinatingAccessTo: url)
        }
        return url
    }

    func createLocalUrl(id: UUID, pathExtension: String) async throws -> URL? {
        try await url(id: id, location: .local, pathExtension: pathExtension, cloudUrl: nil)
    }

    func remove(url: URL) async throws {
        try await FileManager.default.removeItem(coordinatingAccessAt: url)
    }
}

private extension LocationFileManager {
    private func add(relative url: URL, to root: URL) -> URL {
        var pathComponents = url.pathComponents
        if pathComponents.first == "/" {
            pathComponents.removeFirst()
        }
        var result = root
        for component in pathComponents {
            result.append(component: component)
        }
        return result
    }

    private func createDirectory(url: URL) async throws {
        let (exists, _) = try await FileManager.default.fileExists(coordinatingAccessAt: url)
        guard !exists else { return }
        try await FileManager.default.createDirectory(coordinatingAccessAt: url, withIntermediateDirectories: true)
    }

    private func subfolder(for id: UUID) -> String {
        String(id.uuidString.suffix(2))
    }

    private func url(id: UUID, location: FileLocation, pathExtension: String, cloudUrl: URL?) async throws -> URL? {
        var rootUrl: URL?
        switch location {
        case .local:
            rootUrl = rootLocal
        case .appCloud:
            rootUrl = rootAppCloud
        case .icloud:
            return cloudUrl
        case .other, .url, .newCloud:
            return nil
        }
        guard var fileURL = rootUrl?
            .appendingPathComponent(moduleFolder, isDirectory: true)
            .appendingPathComponent(subfolder(for: id), isDirectory: true) else { return nil }
        try await createDirectory(url: fileURL)
        fileURL = fileURL
            .appendingPathComponent(id.uuidString, isDirectory: false)
            .appendingPathExtension(pathExtension)
        return fileURL
    }
}
