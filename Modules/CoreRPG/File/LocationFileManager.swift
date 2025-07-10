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
        return .cloud
    }

    func relativeUrl(for url: URL?) -> URL? {
        guard let url, let location = fileLocation(for: url) else { return url }
        switch location {
        default:
            return url
        }
    }

    func absoluteUrl(for url: URL?, at location: FileLocation, module: String? = nil) -> URL? {
        guard let url else { return url }
        switch location {
        case .cloud:
            return add(relative: url, to: rootNewCloud, module: module)
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

    func remove(url: URL) async throws {
        try await FileManager.default.removeItem(coordinatingAccessAt: url)
    }
}

private extension LocationFileManager {
    private func add(relative url: URL, to root: URL, module: String?) -> URL {
        var pathComponents = url.pathComponents
        if pathComponents.first == "/" {
            pathComponents.removeFirst()
        }
        var result = root
        if let module {
            result.append(component: module)
        }
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
        return nil
    }
}
