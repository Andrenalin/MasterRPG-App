// @copyright André Trettin

import AdventureRPG
import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import SwiftUI
import TableRPG
import WeatherRPG

#if !os(tvOS)
import GeneratorRPG
#endif

/// Identifies which window owns the navigator a router is bound to.
public enum WindowRole {
    case game
    case editor
    case search
    case settings
}

/// Single router whose action list is parameterised by the owning window's role and the
/// active platform. Replaces the three previous platform-specific routers.
public struct WindowRouter: NavigationRouteHandling {
    public init(appModel: AppModel, role: WindowRole) {
        self.appModel = appModel
        self.role = role
    }

    let appModel: AppModel
    let role: WindowRole

    @MainActor public func route(to route: KnownRoutes, with navigator: Navigator) {
        navigator.perform(actions: actions(for: route))
    }

    @MainActor func actions(for route: KnownRoutes) -> [NavigationAction] {
        switch role {
        case .game:
            return gameWindowActions(for: route)
        case .editor:
            return editorWindowActions(for: route)
        case .search:
            return searchWindowActions(for: route)
        case .settings:
            return settingsWindowActions(for: route)
        }
    }
}

// MARK: - Game window

private extension WindowRouter {
    /// The Game window hosts different content per platform:
    /// - iOS / iPadOS / tvOS: every module surfaces here (single-window app).
    /// - macOS: only `.game` shows here; `.search` and `.setting` have their own windows; every
    ///   other module is forwarded to the Editor window.
    /// - visionOS: `visionTabs` (game, adventures, values, generator, search, settings) plus the editor flips
    ///   `RootRoute.editors` → `ExtendedTabRoute.X` for material modules.
    @MainActor func gameWindowActions(for route: KnownRoutes) -> [NavigationAction] {
#if os(macOS)
        switch route {
        case .game:
            return [.send(RootRoute.game)]
        default:
            // Search / settings / editor-window routes don't belong in the macOS Game window —
            // surface them in the right window.
            return forwardToOtherWindow(for: route)
        }
#elseif os(visionOS)
        return visionGameWindowActions(for: route)
#else
        // iOS / iPadOS / tvOS — single window owns every module. Layout decides whether the route
        // surfaces as a top-level RootRoute or via the editors→ExtendedTabRoute compound.
        return compactOrSplitGameActions(for: route)
#endif
    }

#if !os(macOS) && !os(visionOS)
    @MainActor func compactOrSplitGameActions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(let itemId, _):
            return adventureActions(itemId: itemId)
        case .audios(let itemId, _):
            return editorTabActions(rootRoute: .audios, extendedTab: .audios, detail: itemId.map { AudioRoute.detail($0) })
        case .dice(let itemId, _):
            return editorTabActions(rootRoute: .dice, extendedTab: .dice, detail: itemId.map { DiceRoute.detail($0) })
        case .game:
            return [.send(RootRoute.game)]
        case .generators(let itemId, _):
#if !os(tvOS)
            return editorTabActions(rootRoute: .generator, extendedTab: .generator, detail: itemId.map { GeneratorRoute.detail($0) })
#else
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.generator)]
#endif
        case .maps(let itemId, _):
            return editorTabActions(rootRoute: .maps, extendedTab: .maps, detail: itemId.map { MapRoute.detail($0) })
        case .pdfs(let itemId, _):
            return editorTabActions(rootRoute: .pdfs, extendedTab: .pdfs, detail: itemId.map { PdfRoute.detail($0) })
        case .photos(let itemId, _):
            return editorTabActions(rootRoute: .photos, extendedTab: .photos, detail: itemId.map { PhotoRoute.detail($0) })
        case .spaces(let itemId, _):
            return editorTabActions(rootRoute: .space, extendedTab: .space, detail: itemId.map { SpaceRoute.detail($0) })
        case .search:
            return [.send(RootRoute.search)]
        case .settings:
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.settings)]
        case .tables(let itemId, _):
            return editorTabActions(rootRoute: .tables, extendedTab: .tables, detail: itemId.map { TableRoute.detail($0) })
        case .values(let itemId, _):
            return charactersActions(itemId: itemId)
        case .weathers(let itemId, _):
            return editorTabActions(rootRoute: .weathers, extendedTab: .weathers, detail: itemId.map { WeatherRoute.detail($0) })
        @unknown default:
            return []
        }
    }

    /// On compact layouts (iPhone) the route surfaces via editors→ExtendedTabRoute.X; on regular split
    /// layouts (iPad/Mac sidebar) it surfaces directly as the top-level RootRoute. We dispatch on the
    /// stored navigation type so a single router handles both.
    ///
    /// Skips `.reset` and the detail push when `detail` is nil — the route was a "show module" command
    /// (e.g. macOS menu "Show Dice") that should bring the module forward without clearing whatever
    /// item the user has currently selected.
    @MainActor func editorTabActions(rootRoute: RootRoute, extendedTab: ExtendedTabRoute, detail: (any Hashable)?) -> [NavigationAction] {
        if isCompactLayout {
            guard let detail else { return [.send(RootRoute.editors), .send(extendedTab)] }
            return [.send(RootRoute.editors), .reset, .send(extendedTab), .send(detail)]
        }
        guard let detail else { return [.send(rootRoute)] }
        return [.send(rootRoute), .reset, .send(detail)]
    }

    @MainActor func adventureActions(itemId: UUID?) -> [NavigationAction] {
        guard let itemId else { return [.send(RootRoute.adventures)] }
        return [.send(RootRoute.adventures), .reset, .send(AdventureRoute.detail(itemId))]
    }

    @MainActor func charactersActions(itemId: UUID?) -> [NavigationAction] {
        guard let itemId else { return [.send(RootRoute.values)] }
        return [.send(RootRoute.values), .reset, .send(CharacterRoute.detail(itemId))]
    }

    @MainActor var isCompactLayout: Bool {
        appModel.isCompactGameWindow
    }
#endif

#if os(visionOS)
    @MainActor func visionGameWindowActions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(let itemId, _):
            return rootAndDetailActions(rootRoute: .adventures, detail: itemId.map { AdventureRoute.detail($0) })
        case .game:
            return [.send(RootRoute.game)]
        case .generators(let itemId, _):
            return rootAndDetailActions(rootRoute: .generator, detail: itemId.map { GeneratorRoute.detail($0) })
        case .search:
            return [.send(RootRoute.search)]
        case .settings:
            return [.send(RootRoute.settings)]
        case .values(let itemId, _):
            return rootAndDetailActions(rootRoute: .values, detail: itemId.map { CharacterRoute.detail($0) })
        default:
            // Editor-window-bound routes — open the editor window and let its router handle them.
            return forwardToOtherWindow(for: route)
        }
    }
#endif

    @MainActor func forwardToOtherWindow(for route: KnownRoutes) -> [NavigationAction] {
        let module = networkModule(for: route)
#if os(macOS)
        // Settings has its own SwiftUI Settings window — opened via Cmd-, not by ScenesManager.
        if module == .setting {
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(150))
                appModel.navigator(for: module).perform(route: route)
            }
            return []
        }
#endif
        appModel.routeToModule(module, itemId: itemId(for: route), entryId: entryId(for: route))
        return []
    }
}

// MARK: - Editor window

private extension WindowRouter {
    /// The Editor window only exists on macOS and visionOS, and hosts the editor tabs.
    /// Routes for `.game` / `.search` / `.setting` are forwarded back to whichever window owns them.
    @MainActor func editorWindowActions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .adventures, module: .adventure, itemId: itemId)
        case .audios(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .audios, module: .audio, itemId: itemId)
        case .dice(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .dice, module: .dice, itemId: itemId)
        case .generators(let itemId, _):
#if !os(tvOS)
            return rootAndDirectSelectionActions(rootRoute: .generator, module: .generator, itemId: itemId)
#else
            return [.send(RootRoute.generator)]
#endif
        case .maps(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .maps, module: .map, itemId: itemId)
        case .pdfs(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .pdfs, module: .pdf, itemId: itemId)
        case .photos(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .photos, module: .photo, itemId: itemId)
        case .spaces(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .space, module: .space, itemId: itemId)
        case .tables(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .tables, module: .table, itemId: itemId)
        case .values(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .values, module: .value, itemId: itemId)
        case .weathers(let itemId, _):
            return rootAndDirectSelectionActions(rootRoute: .weathers, module: .weather, itemId: itemId)
        case .game, .search, .settings:
            return forwardToOtherWindow(for: route)
        @unknown default:
            return []
        }
    }

    /// Builds the action sequence for "navigate to module (optionally to a specific item)".
    ///
    /// When `detail` is provided we pop the stack first (`.reset`) so the new detail replaces whatever
    /// was there. When it's nil — e.g. the macOS menu's "Show <Module>" item — we only switch the root
    /// route and leave the existing list selection / pushed detail alone, so users don't lose context
    /// just because they clicked the module's menu entry.
    @MainActor func rootAndDetailActions(rootRoute: RootRoute, detail: (any Hashable)?) -> [NavigationAction] {
        guard let detail else { return [.send(rootRoute)] }
        return [.send(rootRoute), .reset, .send(detail)]
    }

    /// Variant used by the macOS Editor window: switches the tab via `RootRoute` and writes the
    /// item selection directly onto the module's navigation model instead of deep-linking through
    /// a `ModuleRoute.detail(itemId)` send.
    ///
    /// **Why:** Inside `TabbedSplitNavigation` the selected tab body is rendered through a
    /// `ManagedPresentationView`, which creates a child navigator. After `.reset` runs
    /// `dismissAny + popAny` recursively across the tree, the publisher's downstream
    /// `AdventureRoute` (etc.) send arrives before the module's body has a re-subscribed
    /// receiver — the broadcast deinits with `missing receive handler`. Writing the selection
    /// directly through the controller's `navigationModel.selectedItemId` is what each module's
    /// `StateRestorationView` already syncs from anyway, so the visible state is identical and
    /// the timing problem disappears.
    ///
    /// The selection write is queued as a `NavigationAction` AFTER the `RootRoute.X` send so the
    /// destination module's body has time to mount and register its `.onChange(navigationModel
    /// .selectedItemId)` watcher before the value flips. Writing synchronously here would set the
    /// value before the StateRestorationView's `onAppear` ran, and the SceneStorage-empty branch
    /// would clobber it back to nil.
    @MainActor func rootAndDirectSelectionActions(rootRoute: RootRoute, module: NetworkModules, itemId: UUID?) -> [NavigationAction] {
        guard let itemId else { return [.send(rootRoute)] }
        let appModel = self.appModel
        let assignSelection: NavigationAction = .action { _ in
            appModel.itemRootController(for: module)?.navigationModel.selectedItemId = itemId
            return .auto
        }
        return [.send(rootRoute), assignSelection]
    }
}

// MARK: - Search window

private extension WindowRouter {
    /// The Search window (macOS only) handles only `.search`; everything else is forwarded
    /// to the window that owns the route.
    @MainActor func searchWindowActions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .search:
            return [.send(RootRoute.search)]
        default:
            return forwardToOtherWindow(for: route)
        }
    }
}

// MARK: - Settings window

private extension WindowRouter {
    /// The Settings window (macOS only) handles only `.settings`; everything else is forwarded.
    @MainActor func settingsWindowActions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .settings:
            return [.send(RootRoute.settings)]
        default:
            return forwardToOtherWindow(for: route)
        }
    }
}

// MARK: - Helpers

private extension WindowRouter {
    func networkModule(for route: KnownRoutes) -> NetworkModules {
        switch route {
        case .adventures: return .adventure
        case .audios: return .audio
        case .dice: return .dice
        case .game: return .game
        case .generators: return .generator
        case .maps: return .map
        case .pdfs: return .pdf
        case .photos: return .photo
        case .spaces: return .space
        case .search: return .search
        case .settings: return .setting
        case .tables: return .table
        case .values: return .value
        case .weathers: return .weather
        @unknown default: return .none
        }
    }

    func itemId(for route: KnownRoutes) -> UUID? {
        switch route {
        case .adventures(let itemId, _), .audios(let itemId, _), .dice(let itemId, _),
             .generators(let itemId, _), .maps(let itemId, _), .pdfs(let itemId, _),
             .photos(let itemId, _), .spaces(let itemId, _), .tables(let itemId, _),
             .values(let itemId, _), .weathers(let itemId, _):
            return itemId
        case .game, .search, .settings:
            return nil
        @unknown default:
            return nil
        }
    }

    func entryId(for route: KnownRoutes) -> UUID? {
        switch route {
        case .adventures(_, let entryId), .audios(_, let entryId), .dice(_, let entryId),
             .generators(_, let entryId), .maps(_, let entryId), .pdfs(_, let entryId),
             .photos(_, let entryId), .spaces(_, let entryId), .tables(_, let entryId),
             .values(_, let entryId), .weathers(_, let entryId):
            return entryId
        case .game, .search, .settings:
            return nil
        @unknown default:
            return nil
        }
    }
}
