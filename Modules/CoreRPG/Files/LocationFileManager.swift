// @copyright André Trettin

import Foundation

/// The roots are read lazily, not captured at init: every module's file controller builds
/// one from `@MainActor` initializers during `AppModel` setup, which used to resolve the iCloud
/// container synchronously on the main thread at launch (racing the off-main prewarm), and a
/// captured value also never followed an iCloud identity change. See CODE_AUDIT_18 §3.3.
public struct LocationFileManager: Sendable {
    let moduleFolder: String

    var rootAppCloud: URL? {
        FileManager.cloudURL?.appending(path: CloudDocumentController.documentDirName)
    }

    var rootLocal: URL? {
        URL.documentsDirectory
    }

    var rootICloud: URL? {
        FileManager.cloudURL?.deletingLastPathComponent().appending(path: "com~apple~CloudDocs/")
    }

    var rootNewCloud: URL {
        FileManager.preferredRootUrl.appending(path: CloudDocumentController.documentDirName)
    }

    public init(moduleFolder: String) {
        self.moduleFolder = moduleFolder
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
            return URL(string: url.absoluteString.replacing(cloudPath.absoluteString, with: ""))
        case .icloud:
            guard let cloudPath = rootICloud else { return url }
            return URL(string: url.absoluteString.replacing(cloudPath.absoluteString, with: ""))
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
            // Imported references never get here without a `Documents` component:
            // `FileUrl.sanitizedForImport` relocates them (CODE_AUDIT_28 §6.1). The resolver keeps
            // the absolute path for the app's own `.local` files outside it.
            guard let documentsIndex = url.pathComponents.firstIndex(of: CloudDocumentController.documentDirName) else {
                return url
            }
            var newUrl = rootLocal
            // See CODE_AUDIT_15 §5.1: never let `..` climb out of the documents directory.
            CloudDocumentController.safeComponents(Array(url.pathComponents[(documentsIndex + 1)...])).forEach {
                newUrl.append(path: $0)
            }
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
        // See CODE_AUDIT_15 §5.1: `..` segments of a decoded url must not leave `root`.
        let pathComponents = CloudDocumentController.safeComponents(url.pathComponents)
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
