// @copyright André Trettin


import CoreRPG
import SwiftUI
import AdventureRPG

public struct RootURLHandler: NavigationURLHandler {
    public init(appModel: AppModel) {
        self.appModel = appModel
    }
    
    let appModel: AppModel
    
    @MainActor public func handles(_ url: URL, with navigator: Navigator) -> Bool {
        guard !url.isGmzDocument else {
            // GMZ document — surface the import in the Settings tab so the user can see progress.
            if appModel.appNavigationModel.initialRouteType == .ready {
                navigator.perform(route: KnownRoutes.settings)
                _ = appModel.adventureRoot.importControllable.importUrl(from: url)
            }
            return true
        }

        let module = url.moduleIdentifier
        guard module != .none else { return false }
        navigator.perform(route: KnownRoutes.route(module: module, itemId: url.itemId, entryId: url.childId))
        return true
    }
}
