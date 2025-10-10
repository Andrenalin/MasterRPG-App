// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG
import SwiftUI

struct RootFiveRouteRouter: NavigationRouteHandling {
    let appModel: AppModel
    
    @MainActor func route(to route: KnownRoutes, with navigator: Navigator) {
        navigator.perform(actions: actions(for: route))
    }
    
    @MainActor func actions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.adventures), .reset]
            if let itemId {
                routes.append(.send(AdventureRoute.detail(itemId)))
            }
            return routes
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
        case .generators(let itemId, _):

            var routes: [NavigationAction] = [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.generator)]
#if !os(tvOS)
            if let itemId {
                routes.append(.send(GeneratorRoute.detail(itemId)))
            }
#endif
            return routes
        case .maps(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.maps)]
            if let itemId {
                routes.append(.send(MapRoute.detail(itemId)))
            }
            return routes
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
        case .tables(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.editors), .reset, .send(ExtendedTabRoute.tables)]
            if let itemId {
                routes.append(.send(TableRoute.detail(itemId)))
            }
            return routes
        case .values(let itemId, _):
            var routes: [NavigationAction] = [.send(RootRoute.values), .reset]
            if let itemId {
                routes.append(.send(CharacterRoute.detail(itemId)))
            }
            return routes
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
