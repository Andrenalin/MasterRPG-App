// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import SwiftUI
import PhotoRPG
import SpaceRPG

struct RootRouteRouter: NavigationRouteHandling {
    let appModel: AppModel
    
    @MainActor func route(to route: KnownRoutes, with navigator: Navigator) {
        navigator.perform(actions: actions(for: route))
    }
    
    @MainActor func actions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(_, _):
            return [.send(RootRoute.adventures)]
        case .audios(_, _):
            return [.send(RootRoute.audios)]
        case .dice(_, _):
            return [.send(RootRoute.dice)]
        case .game:
            return [.send(RootRoute.game)]
        case .maps(_, _):
            return [.send(RootRoute.maps)]
        case .pdfs(_, _):
            return [.send(RootRoute.pdfs)]
        case .photos(let itemId, _):
            if let itemId {
                return [.send(RootRoute.photos), .send(PhotoRoute.detail(itemId))]
            }
            return [.send(RootRoute.photos)]
        case .spaces(let itemId, _):
            if let itemId {
                return [.send(RootRoute.space), .send(SpaceRoute.detail(itemId))]
            }
            return [.send(RootRoute.space)]
        case .settings:
            return [.send(RootRoute.editors)]
        case .tables(_, _):
            return [.send(RootRoute.tables)]
        case .values(_, _):
            return [.send(RootRoute.values)]
        case .weathers(_, _):
            return [.send(RootRoute.weathers)]
        @unknown default:
            fatalError()
        }
    }
}


struct RootFiveRouteRouter: NavigationRouteHandling {
    let appModel: AppModel
    
    @MainActor func route(to route: KnownRoutes, with navigator: Navigator) {
        navigator.perform(actions: actions(for: route))
    }
    
    @MainActor func actions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(_, _):
            return [.send(RootRoute.adventures)]
        case .audios(_, _):
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.audios)]
        case .dice(_, _):
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.dice)]
        case .game:
            return [.send(RootRoute.game)]
        case .maps(_, _):
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.maps)]
        case .pdfs(_, _):
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.pdfs)]
        case .photos(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.photos)]
            if let itemId {
                routes.append(.send(PhotoRoute.detail(itemId)))
            }
            return routes
        case .spaces(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.photos)]
            if let itemId {
                routes.append(.send(SpaceRoute.detail(itemId)))
            }
            return routes
        case .settings:
            return [.send(RootRoute.settings)]
        case .tables(_, _):
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.tables)]
        case .values(_, _):
            return [.send(RootRoute.values)]
        case .weathers(_, _):
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.weathers)]
        @unknown default:
            fatalError()
        }
    }
}
