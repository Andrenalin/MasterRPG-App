// @copyright André Trettin


import CoreRPG
import SwiftUI
import AdventureRPG

public struct RootURLHandler: NavigationURLHandler {
    public init(appModel: AppModel, role: WindowRole) {
        self.appModel = appModel
        self.role = role
    }

    let appModel: AppModel
    let role: WindowRole

    @MainActor public func handles(_ url: URL, with navigator: Navigator) -> Bool {
        // Only real files are importable documents; an `RPG://…/x.gmz` or web URL that merely
        // ends in a document extension is not. See CODE_AUDIT_15 §5.12.
        if url.isFileURL, url.isVTTImportDocument {
            return handleVTT(url: url, with: navigator)
        }

        if url.isFileURL, url.isGmzDocument {
            return handleGmz(url: url, with: navigator)
        }

        let module = url.moduleIdentifier
        guard module != .none else { return false }

        guard appModel.appNavigationModel.initialRouteType == .ready else {
            appModel.routeToModuleWhenReady(
                module,
                itemId: url.itemId,
                entryId: url.childId
            )
            return true
        }

        let target = appModel.navigator(for: module)
        if target === navigator {
            navigator.perform(route: KnownRoutes.route(module: module, itemId: url.itemId, entryId: url.childId))
        } else {
            appModel.routeToModule(module, itemId: url.itemId, entryId: url.childId)
        }
        return true
    }

    /// A document open request presents the import UI but never starts importing.
    /// The URL is displayed first and the user must explicitly approve it.
    @MainActor private func handleGmz(url: URL, with navigator: Navigator) -> Bool {
        appModel.presentImport(url, with: navigator)
        return true
    }

    @MainActor private func handleVTT(url: URL, with navigator: Navigator) -> Bool {
        appModel.presentVTTImport(url, with: navigator)
        return true
    }
}

private extension URL {
    var isVTTImportDocument: Bool {
        switch pathExtension.lowercased() {
        case "uvtt", "dd2vtt", "mrpgfoundry": true
        default: false
        }
    }
}
