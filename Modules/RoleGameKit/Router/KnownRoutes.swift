// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGAdventures
import RPGAudios
import SwiftUI
import RPGDie
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import RPGWeathers

struct RootRouteRouter: NavigationRouteHandling {
    let appModel: AppStore
    
    @MainActor func route(to route: KnownRoutes, with navigator: Navigator) {
        navigator.perform(actions: actions(for: route))
    }
    
    @MainActor func actions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(let itemId, _):
            if let itemId {
                return [.send(RootRoute.adventures), .reset, .send(AdventureRoute.detail(itemId))]
            }
            return [.send(RootRoute.adventures)]
        case .audios(let itemId, _):
            if let itemId {
                return [.send(RootRoute.audios), .reset, .send(AudioRoute.detail(itemId))]
            }
            return [.send(RootRoute.audios)]
        case .dice(let itemId, _):
            if let itemId {
                return [.send(RootRoute.dice), .reset, .send(DiceRoute.detail(itemId))]
            }
            return [.send(RootRoute.dice)]
        case .game:
            return [.send(RootRoute.game)]
        case .generators(let itemId, _):
//            #if !os(tvOS)
//            if let itemId {
//                return [.send(RootRoute.generator), .reset, .send(GeneratorRoute.detail(itemId))]
//            }
//            #endif
            return [.send(RootRoute.generator)]
        case .maps(let itemId, _):
            if let itemId {
                return [.send(RootRoute.maps), .reset, .send(MapRoute.detail(itemId))]
            }
            return [.send(RootRoute.maps)]
        case .pdfs(let itemId, _):
            if let itemId {
                return [.send(RootRoute.pdfs), .reset, .send(PdfRoute.detail(itemId))]
            }
            return [.send(RootRoute.pdfs)]
        case .photos(let itemId, _):
            if let itemId {
                return [.send(RootRoute.photos), .reset, .send(PhotoRoute.detail(itemId))]
            }
            return [.send(RootRoute.photos)]
        case .spaces(let itemId, _):
            if let itemId {
                return [.send(RootRoute.space), .reset, .send(SpaceRoute.detail(itemId))]
            }
            return [.send(RootRoute.space)]
        case .search:
            return [.send(RootRoute.search)]
        case .settings:
            return [.send(RootRoute.editors)]
        case .tables(let itemId, _):
            if let itemId {
                return [.send(RootRoute.tables), .reset, .send(TableRoute.detail(itemId))]
            }
            return [.send(RootRoute.tables)]
        case .values(let itemId, _):
            if let itemId {
                return [.send(RootRoute.values), .reset, .send(CharacterRoute.detail(itemId))]
            }
            return [.send(RootRoute.values)]
        case .weathers(let itemId, _):
            if let itemId {
                return [.send(RootRoute.weathers), .reset, .send(WeatherRoute.detail(itemId))]
            }
            return [.send(RootRoute.weathers)]
        @unknown default:
            fatalError()
        }
    }
}


struct RootFiveRouteRouter: NavigationRouteHandling {
    let appModel: AppStore
    
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
//#if !os(tvOS)
//            if let itemId {
//                routes.append(.send(GeneratorRoute.detail(itemId)))
//            }
//#endif
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
