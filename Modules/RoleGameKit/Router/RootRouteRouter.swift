// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGAdventures
import AudioRPG
import SwiftUI
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG

#if !os(tvOS)
import GeneratorRPG
#endif

struct RootRouteRouter: NavigationRouteHandling {
    let appModel: AppModel
    
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
            #if !os(tvOS)
            if let itemId {
                return [.send(RootRoute.generator), .reset, .send(GeneratorRoute.detail(itemId))]
            }
            #endif
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
