// @copyright André Trettin

import AndrenalinKit
import SwiftUI
import RPGAdventures

public struct RootURLHandler: NavigationURLHandler {
    public init(appStore: AppStore) {
        self.appStore = appStore
    }
    
    let appStore: AppStore
    
    @MainActor public func handles(_ url: URL, with navigator: Navigator) -> Bool {
        guard !url.isGmzDocument else {
            // GMZ document
            if appStore.hasDatabase {
                _ = appStore.adventureRoot.importControllable.importUrl(from: url)
            }
            return true
        }

        let module = url.moduleIdentifier
        guard module != .none else { return false }
        navigator.perform(route: KnownRoutes.route(module: module, itemId: url.itemId, entryId: url.childId))
        return true
    }
}
