// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftUI
import os.log

// MARK: - Routing

extension AppModel {
    @MainActor public func presentImport(_ url: URL, with navigator: Navigator) {
        guard pendingImportURL != url else { return }
        securityScopedImportURL?.stopAccessingSecurityScopedResource()
        securityScopedImportURL = url.startAccessingSecurityScopedResource() ? url : nil
        pendingImportURL = url
        guard appNavigationModel.initialRouteType == .ready else {
            pendingImportNavigator = navigator
            return
        }
        navigator.navigate(to: SettingsRoute.importData, method: .managedCover)
    }

    @MainActor public func presentVTTImport(_ url: URL, with navigator: Navigator) {
        guard pendingVTTImportURL != url else { return }
        pendingVTTImportURL = url
        guard appNavigationModel.initialRouteType == .ready else {
            pendingVTTImportNavigator = navigator
            return
        }
        presentVTTImport(with: navigator)
    }

    @MainActor public func finishImportPresentation() {
        securityScopedImportURL?.stopAccessingSecurityScopedResource()
        securityScopedImportURL = nil
        pendingImportNavigator = nil
        pendingImportURL = nil
    }

    /// Opens what a continued activity names: the app's own Handoff activity, or (not on tvOS) a tap
    /// on a Core Spotlight result. Returns whether the activity was one of these, so a delegate can
    /// report it as handled. The Spotlight route is resolved once the database is ready.
    /// See CODE_AUDIT_AppIntents2 §4.1.
    @MainActor @discardableResult
    public func continueActivity(_ userActivity: NSUserActivity) -> Bool {
        if userActivity.activityType == UserActivity.bundleIdentifierType {
            let module = UserActivity.module(from: userActivity)
            guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return false }
            routeToModuleWhenReady(module, itemId: itemId, entryId: UserActivity.childId(from: userActivity))
            return true
        }
#if !os(tvOS)
        guard SpotlightActivityRoute.isSpotlightActivity(userActivity) else { return false }
        Task { @MainActor in
            await DatabaseReadiness.wait()
            guard let context = databaseModel.context,
                  let route = await SpotlightActivityRoute.resolve(userActivity, in: context)
            else {
                Logger.bootStrap.info("A Spotlight result did not resolve to an item")
                return
            }
            routeToModuleWhenReady(route.module, itemId: route.itemId, entryId: route.entryId)
        }
        return true
#else
        return false
#endif
    }

    @MainActor public func routeToModuleWhenReady(
        _ module: NetworkModules,
        itemId: UUID? = nil,
        entryId: UUID? = nil
    ) {
        guard admitsExternalRoute(module, itemId: itemId, entryId: entryId) else { return }

        guard appNavigationModel.initialRouteType == .ready else {
            pendingExternalRoute = PendingExternalRoute(module: module, itemId: itemId, entryId: entryId)
            return
        }
        routeToModule(module, itemId: itemId, entryId: entryId)
    }

    /// Whether a route that came from outside the app (a link, a widget, a continued activity)
    /// should run: `false` for the same route within a second of the last one, which is one
    /// request delivered twice. Records the route. See CODE_AUDIT_21 §5.26.
    @MainActor public func admitsExternalRoute(
        _ module: NetworkModules,
        itemId: UUID? = nil,
        entryId: UUID? = nil
    ) -> Bool {
        let requestedRoute = PendingExternalRoute(module: module, itemId: itemId, entryId: entryId)
        let now = Date.now
        guard requestedRoute != lastExternalRoute
                || now.timeIntervalSince(lastExternalRouteDate) >= 1 else { return false }
        lastExternalRoute = requestedRoute
        lastExternalRouteDate = now
        return true
    }

    func presentPendingExternalNavigationIfNeeded() {
        if let navigator = pendingImportNavigator, pendingImportURL != nil {
            pendingImportNavigator = nil
            navigator.navigate(to: SettingsRoute.importData, method: .managedCover)
        }
        if let navigator = pendingVTTImportNavigator, pendingVTTImportURL != nil {
            pendingVTTImportNavigator = nil
            presentVTTImport(with: navigator)
        }
        if let route = pendingExternalRoute {
            pendingExternalRoute = nil
            routeToModule(route.module, itemId: route.itemId, entryId: route.entryId)
        }
    }

    private func presentVTTImport(with navigator: Navigator) {
#if os(macOS)
        let target = settingsNavigator
        scenesManager.openSettingsWindow()
#else
        let target = gameNavigator
#endif

        Task { @MainActor in
            // A route sent before the target window's stack mounted is buffered and replayed
            // when it mounts (CODE_AUDIT_18 §3.17). The short delay is kept only so the
            // settings route has applied before the import cover is presented on top of it.
            // See CODE_AUDIT_20 §4.4.
            target.perform(route: KnownRoutes.settings)
            try? await Task.sleep(for: NavigationTiming.crossWindowRouteDelay)
            target.navigate(to: SettingsRoute.importData, method: .managedCover)
        }
    }

    @MainActor
    public func presentImportScreen() {
#if os(macOS)
        let target = settingsNavigator
        scenesManager.openSettingsWindow()
#else
        let target = gameNavigator
#endif

        Task { @MainActor in
            target.perform(route: KnownRoutes.settings)
            try? await Task.sleep(for: NavigationTiming.crossWindowRouteDelay)
            target.navigate(to: SettingsRoute.importData, method: .managedCover)
        }
    }

    @MainActor
    public func refreshTipEligibility() {
        MasterRPGTips.refreshEligibility(
            rootManager: root,
            databaseReady: appNavigationModel.initialRouteType == .ready
        )
    }

    func itemRootController(for module: NetworkModules) -> ItemRootController? {
        root.itemRootController(for: module)
    }

    /// Returns the Navigator that owns the window where the given module surfaces.
    /// - macOS: editor modules → `editorNavigator`, `.setting` → `settingsNavigator`, else `gameNavigator`.
    /// - visionOS: editor modules → `editorNavigator` (Settings stays in Game window), else `gameNavigator`.
    /// - iOS / iPadOS / tvOS: always `gameNavigator` (editor lives as tabs inside the Game window).
    @MainActor public func navigator(for module: NetworkModules) -> Navigator {
        navigator(forScene: module.sceneId)
    }

    /// Returns the root Navigator for the given window scene.
    ///
    /// Callers that have just opened a window for a module should resolve the
    /// navigator through this method so the navigator they get matches the window that's actually
    /// on screen — looking it up on the module before the window opens can yield the wrong one
    /// on platforms where module-to-window mapping is platform-conditional.
    ///
    /// Named `forScene:` rather than overloading `for:` so call sites passing leaf-static members
    /// (`.game`, `.search`, ...) don't become ambiguous between `NetworkModules` and `SceneId`.
    @MainActor public func navigator(forScene sceneId: SceneId) -> Navigator {
        switch sceneId {
        case .editor: return editorNavigator
        case .search: return searchNavigator
        case .settings: return settingsNavigator
        default: return gameNavigator
        }
    }

    /// Remembers the module and item on screen before a size class change rebuilds the layout.
    /// In the compact layout the `.editors` tab hosts the module chosen in the extended tab bar,
    /// so that module is the one to remember.
    @MainActor func rememberRouteForLayoutChange() {
        let module = selectedModule?.module == .editor ? selectedExtendedModule?.module : selectedModule?.module
        let itemId = module.flatMap { root[$0]?.currentSelectedItemId }
        guard let module else { return }
        layoutRestoreTarget = LayoutRestoreTarget(module: module, itemId: itemId)
    }

    /// Selects the remembered module and item in the layout that replaced the old one, then clears it.
    /// The regular layout selects the module as a tab; the compact layout reaches it through the
    /// editors tab, which `WindowRouter` handles when it flattens the route.
    @MainActor func restoreRouteAfterLayoutChange(isCompact: Bool) {
        guard let target = layoutRestoreTarget else { return }
        layoutRestoreTarget = nil
        if !isCompact {
            selectedModule = RootRoute(networkModule: target.module)
        }
        navigator(for: target.module).perform(route: KnownRoutes.route(module: target.module, itemId: target.itemId, entryId: nil))
    }

    @MainActor public var routeActions: RouteActions {
        RouteActions(id: .object(ObjectIdentifier(self))) { [weak self] module, itemId, entryId in
            guard let self, module != .none else { return }
            self.routeToModule(module, itemId: itemId, entryId: entryId)
        }
    }

    /// Opens the window that owns `module` (if needed) and performs the corresponding `KnownRoutes`
    /// route on that window's root navigator. A route sent before the new window's stack has
    /// subscribed is buffered by the navigator and replayed once it mounts (CODE_AUDIT_18 §3.17).
    ///
    /// Detail navigation rides through the route as a deep link: when `itemId` is non-nil the
    /// router emits `[.send(RootRoute.X), .reset, .send(ModuleRoute.detail(itemId))]`, and each
    /// module's root view has an `onNavigationReceive` for its own route type that writes the
    /// selection into `navigationModel.selectedItemId`. The 0.8s `assign` delay on the editor
    /// tab receiver gives the module body time to mount before the detail send fires.
    @MainActor public func routeToModule(_ module: NetworkModules, itemId: UUID? = nil, entryId: UUID? = nil) {
        guard module != .none else { return }
        let route = KnownRoutes.route(module: module, itemId: itemId, entryId: entryId)
        _ = scenesManager.openWindow(for: module)
        // When this opened a window, the route is buffered by the navigator until the new
        // window's stack has mounted, instead of a fixed delay that dropped it on slow
        // devices. See CODE_AUDIT_18 §3.17.
        navigator(for: module).perform(route: route)
    }
}

struct LayoutRestoreTarget: Equatable {
    let module: NetworkModules
    let itemId: UUID?
}

struct PendingExternalRoute: Equatable {
    let module: NetworkModules
    let itemId: UUID?
    let entryId: UUID?
}
