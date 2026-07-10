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

    func absoluteUrl(for url: URL?, at location: FileLocation, module: String? = nil) -> URL? {
        guard let url else { return url }
        switch location {
        case .appCloud:
            guard let cloudPath = rootAppCloud else { return nil }
            return add(relative: url, to: cloudPath, module: nil)
        case .icloud:
            guard let cloudPath = rootICloud else { return nil }
            return add(relative: url, to: cloudPath, module: nil)
        case .newCloud:
            return add(relative: url, to: rootNewCloud, module: mapModule(name: module))
        case .local:
            guard let rootLocal else { return nil }
            guard let documentsIndex = url.pathComponents.firstIndex(of: "Documents") else {
                return url
            }
            let filePath = url.pathComponents[(documentsIndex + 1)...].joined(separator: "/")
            let newUrl = rootLocal.appending(path: filePath)
            return newUrl
        default:
            return url
        }
    }
    
    private func mapModule(name: String?) -> String? {
        guard let name else { return nil }
        return switch name {
        case NetworkModules.audio.token: "audio"
        case NetworkModules.pdf.token: "pdf"
        case NetworkModules.photo.token: "photo"
        case NetworkModules.space.token: "space"
        default: name
        }
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

}
