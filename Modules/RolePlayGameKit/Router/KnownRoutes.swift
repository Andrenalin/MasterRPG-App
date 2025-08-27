// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import WeatherRPG
import SwiftUI

struct RootRouteRouter: NavigationRouteHandling {
    let appModel: AppModel
    
    @MainActor func route(to route: KnownRoutes, with navigator: Navigator) {
        navigator.perform(actions: actions(for: route))
    }
    
    @MainActor func actions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(_, _):
            return [.send(RootRoute.adventures)]
        case .audios(let itemId, _):
            if let itemId {
                return [.send(RootRoute.audios), .send(AudioRoute.detail(itemId))]
            }
            return [.send(RootRoute.audios)]
        case .dice(let itemId, _):
            if let itemId {
                return [.send(RootRoute.dice), .send(DiceRoute.detail(itemId))]
            }
            return [.send(RootRoute.dice)]
        case .game:
            return [.send(RootRoute.game)]
        case .maps(_, _):
            return [.send(RootRoute.maps)]
        case .pdfs(let itemId, _):
            if let itemId {
                return [.send(RootRoute.pdfs), .send(PdfRoute.detail(itemId))]
            }
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
        case .search:
            return [.send(RootRoute.search)]
        case .settings:
            return [.send(RootRoute.editors)]
        case .tables(_, _):
            return [.send(RootRoute.tables)]
        case .values(_, _):
            return [.send(RootRoute.values)]
        case .weathers(let itemId, _):
            if let itemId {
                return [.send(RootRoute.weathers), .send(WeatherRoute.detail(itemId))]
            }
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
        case .audios(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.audios)]
            if let itemId {
                routes.append(.send(AudioRoute.detail(itemId)))
            }
            return routes
        case .dice(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.dice)]
            if let itemId {
                routes.append(.send(DiceRoute.detail(itemId)))
            }
            return routes
        case .game:
            return [.send(RootRoute.game)]
        case .maps(_, _):
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.maps)]
        case .pdfs(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.pdfs)]
            if let itemId {
                routes.append(.send(PdfRoute.detail(itemId)))
            }
            return routes
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
        case .search:
            return [.send(RootRoute.search)]
        case .settings:
            return [.send(RootRoute.settings)]
        case .tables(_, _):
            return [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.tables)]
        case .values(_, _):
            return [.send(RootRoute.values)]
        case .weathers(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.weathers)]
            if let itemId {
                routes.append(.send(WeatherRoute.detail(itemId)))
            }
            return routes
        @unknown default:
            fatalError()
        }
    }
}
