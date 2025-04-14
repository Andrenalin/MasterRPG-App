// @copyright André Trettin

import AndrenalinKit
import RPGAdventures
import RPGAudios
import SwiftUI

public enum KnownRoutes: NavigationRoutes {
    case adventures(UUID?, UUID?)
    case audios(UUID?, UUID?)
    case dice(UUID?, UUID?)
    case game
    case maps(UUID?, UUID?)
    case pdfs(UUID?, UUID?)
    case photos(UUID?, UUID?)
    case settings
    case spaces(UUID?, UUID?)
    case tables(UUID?, UUID?)
    case values(UUID?, UUID?)
    case weathers(UUID?, UUID?)
}

extension KnownRoutes {
    static func route(module: NetworkModules, itemId: UUID?, entryId: UUID?) -> KnownRoutes {
        switch module {
        case .adventure: .adventures(itemId, entryId)
        case .audio: .audios(itemId, entryId)
        case .dice: .dice(itemId, entryId)
        case .game: .game
        case .map: .maps(itemId, entryId)
        case .pdf: .pdfs(itemId, entryId)
        case .photo: .photos(itemId, entryId)
        case .setting: .settings
        case .space: .spaces(itemId, entryId)
        case .table: .tables(itemId, entryId)
        case .value: .values(itemId, entryId)
        case .weather: .weathers(itemId, entryId)
        default: .game
        }
    }
}

extension EnvironmentValues {
    @Entry public var router: any NavigationRouting<KnownRoutes> = MockNavigationRouter()
}

struct RootRouteRouter: NavigationRouteHandling {
    let appStore: AppStore
    let tabId: UUID
    
    @MainActor func route(to route: KnownRoutes, with navigator: Navigator) {
        navigator.perform(actions: actions(for: route))
    }
    
    @MainActor func actions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(let itemId, let entryId):
            if let itemId {
                selectItem(for: .adventure, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.adventures(tabId))]
        case .audios(let itemId, let entryId):
            if let itemId {
                selectItem(for: .audio, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.audios(tabId))]
        case .dice(let itemId, let entryId):
            if let itemId {
                selectItem(for: .dice, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.dice(tabId))]
        case .game:
            return [.send(RootRoute.game)]
        case .maps(let itemId, let entryId):
            if let itemId {
                selectItem(for: .map, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.maps(tabId))]
        case .pdfs(let itemId, let entryId):
            if let itemId {
                selectItem(for: .pdf, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.pdfs(tabId))]
        case .photos(let itemId, let entryId):
            if let itemId {
                selectItem(for: .photo, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.photos(tabId))]
        case .spaces(let itemId, let entryId):
            if let itemId {
                selectItem(for: .space, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.space(tabId))]
        case .settings:
            return [.send(RootRoute.editors(tabId))]
        case .tables(let itemId, let entryId):
            if let itemId {
                selectItem(for: .table, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.tables(tabId))]
        case .values(let itemId, let entryId):
            if let itemId {
                selectItem(for: .value, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.values(tabId))]
        case .weathers(let itemId, let entryId):
            if let itemId {
                selectItem(for: .weather, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.weathers(tabId))]
        }
    }
    
    @MainActor func selectItem(for module: NetworkModules, itemId: UUID?, entryId: UUID?) {
        guard let itemId else { return }
        let item = ItemRowModel(itemId: itemId, entryId: entryId, typeId: module)
        switch module {
        case .adventure:
            appStore.adventureRoot.rootModel.selectedItem = item
        case .audio:
            appStore.audioRoot.rootModel.selectedItem = item
        case .dice:
            appStore.diceRoot.rootModel.selectedItem = item
        case .map:
            appStore.mapRoot.rootModel.selectedItem = item
        case .pdf:
            appStore.pdfRoot.rootModel.selectedItem = item
        case .photo:
            appStore.photoRoot.rootModel.selectedItem = item
        case .space:
            appStore.spaceRoot.rootModel.selectedItem = item
        case .table:
            appStore.tableRoot.rootModel.selectedItem = item
        case .value:
            appStore.valueRoot.rootModel.selectedItem = item
        case .weather:
            appStore.weatherRoot.rootModel.selectedItem = item
        default:
            break
        }
    }
}


struct RootFiveRouteRouter: NavigationRouteHandling {
    let appStore: AppStore
    let tabId: UUID
    
    @MainActor func route(to route: KnownRoutes, with navigator: Navigator) {
        navigator.perform(actions: actions(for: route))
    }
    
    @MainActor func actions(for route: KnownRoutes) -> [NavigationAction] {
        switch route {
        case .adventures(let itemId, let entryId):
            if let itemId {
                selectItem(for: .adventure, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.adventures(tabId))]
        case .audios(let itemId, let entryId):
            if let itemId {
                selectItem(for: .audio, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.editors(tabId)), .reset, .send(ExtendedTabRoute.audios)]
        case .dice(let itemId, let entryId):
            if let itemId {
                selectItem(for: .dice, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.editors(tabId)), .reset, .send(ExtendedTabRoute.dice)]
        case .game:
            return [.send(RootRoute.game)]
        case .maps(let itemId, let entryId):
            if let itemId {
                selectItem(for: .map, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.editors(tabId)), .reset, .send(ExtendedTabRoute.maps)]
        case .pdfs(let itemId, let entryId):
            if let itemId {
                selectItem(for: .pdf, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.editors(tabId)), .reset, .send(ExtendedTabRoute.pdfs)]
        case .photos(let itemId, let entryId):
            if let itemId {
                selectItem(for: .photo, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.editors(tabId)), .reset, .send(ExtendedTabRoute.photos)]
        case .spaces(let itemId, let entryId):
            if let itemId {
                selectItem(for: .space, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.editors(tabId)), .reset, .send(ExtendedTabRoute.space)]
        case .settings:
            return [.send(RootRoute.settings)]
        case .tables(let itemId, let entryId):
            if let itemId {
                selectItem(for: .table, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.editors(tabId)), .reset, .send(ExtendedTabRoute.tables)]
        case .values(let itemId, let entryId):
            if let itemId {
                selectItem(for: .value, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.values(tabId))]
        case .weathers(let itemId, let entryId):
            if let itemId {
                selectItem(for: .weather, itemId: itemId, entryId: entryId)
            }
            return [.send(RootRoute.editors(tabId)), .reset, .send(ExtendedTabRoute.weathers)]
        }
    }
    
    @MainActor func selectItem(for module: NetworkModules, itemId: UUID?, entryId: UUID?) {
        guard let itemId else { return }
        let item = ItemRowModel(itemId: itemId, entryId: entryId, typeId: module)
        switch module {
        case .adventure:
            appStore.adventureRoot.rootModel.selectedItem = item
        case .audio:
            appStore.audioRoot.rootModel.selectedItem = item
        case .dice:
            appStore.diceRoot.rootModel.selectedItem = item
        case .map:
            appStore.mapRoot.rootModel.selectedItem = item
        case .pdf:
            appStore.pdfRoot.rootModel.selectedItem = item
        case .photo:
            appStore.photoRoot.rootModel.selectedItem = item
        case .space:
            appStore.spaceRoot.rootModel.selectedItem = item
        case .table:
            appStore.tableRoot.rootModel.selectedItem = item
        case .value:
            appStore.valueRoot.rootModel.selectedItem = item
        case .weather:
            appStore.weatherRoot.rootModel.selectedItem = item
        default:
            break
        }
    }
}
