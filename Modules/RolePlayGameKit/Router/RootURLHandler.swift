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
        guard appModel.appNavigationModel.initialRouteType == .ready else { return false }

        if url.isGmzDocument {
            return handleGmz(url: url, with: navigator)
        }

        let module = url.moduleIdentifier
        guard module != .none else { return false }

        let target = appModel.navigator(for: module)
        if target === navigator {
            navigator.perform(route: KnownRoutes.route(module: module, itemId: url.itemId, entryId: url.childId))
        } else {
            appModel.routeToModule(module, itemId: url.itemId, entryId: url.childId)
        }
        return true
    }

    /// GMZ imports surface in the Settings UI so the user sees progress. Where "Settings" lives depends on platform:
    /// - macOS: dedicated Settings window (`settingsNavigator`).
    /// - visionOS: Settings tab inside the Game window (`gameNavigator`, via editors→ExtendedTabRoute.settings).
    /// - iOS / iPadOS / tvOS: Settings tab inside the Game window (`gameNavigator`).
    @MainActor private func handleGmz(url: URL, with navigator: Navigator) -> Bool {
#if os(macOS)
        let target = appModel.settingsNavigator
#else
        let target = appModel.gameNavigator
#endif

        if target === navigator {
            navigator.perform(route: KnownRoutes.settings)
        } else {
            Task { @MainActor in
                try? await Task.sleep(for: NavigationTiming.crossWindowRouteDelay)
                target.perform(route: KnownRoutes.settings)
            }
        }

        _ = appModel.adventureRoot.importControllable.importUrl(from: url)
        return true
    }
}
