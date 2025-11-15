// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import SwiftUI
import RPGAdventures

public struct RootURLHandler: NavigationURLHandler {
    public init(appModel: AppStore) {
        self.appModel = appModel
    }
    
    let appModel: AppStore
    
    @MainActor public func handles(_ url: URL, with navigator: Navigator) -> Bool {
        guard !url.isGmzDocument else {
            // GMZ document
            if appModel.hasDatabase {
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
