// @copyright André Trettin

import CoreExternalRPG
import AndrenalinKit
import RPGAdventures
import RPGAudios
import RPGDie
import RPGGame
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import RPGWeathers
import SwiftUI

public enum ExtendedTabRoute: String, Hashable, Codable {
    case audios
    case dice
    case maps
    case pdfs
    case photos
    case space
    case tables
    case weathers

    public init(networkModule: NetworkModules) {
        switch networkModule {
        case .audio:
            self = .audios
        case .dice:
            self = .dice
        case .map:
            self = .maps
        case .pdf:
            self = .pdfs
        case .photo:
            self = .photos
        case .space:
            self = .space
        case .table:
            self = .tables
        case .weather:
            self = .weathers
        default:
            self = .pdfs
        }
    }

    public var module: NetworkModules {
        switch self {
            case .audios: .audio
            case .dice: .dice
            case .maps: .map
            case .pdfs: .pdf
            case .photos: .photo
            case .space: .space
            case .tables: .table
            case .weathers: .weather
        }
    }
}

extension ExtendedTabRoute: AppRouter {
    public var title: String {
        String(module.title)
    }

    public var icon: String {
        module.icon
    }
}

extension ExtendedTabRoute: NavigationDestination {
    public var body: some View {
        ExtendedTabRouteDestionationView(route: self)
    }

    static var allTabs: [ExtendedTabRoute] {
        [.pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice]
    }
}

struct ExtendedTabRouteDestionationView: View {
    let route: ExtendedTabRoute
    let tabId = UUID()

    @Environment(AppStore.self) private var appStore

    var body: some View {
        switch route {
            case .audios:
                NewAudioRoute(appStore: appStore, tabId: tabId, isExtended: true)
            case .dice:
                NewDiceRoute(appStore: appStore, tabId: tabId, isExtended: true)
            case .maps:
                MapFactory.rootExtendedView(for: appStore.mapRoot, tabId: tabId)
                    .environment(appStore.mapRoot)
            case .pdfs:
                NewPdfRoute(appStore: appStore, tabId: tabId, isExtended: true)
            case .photos:
                NewPhotoRoute(appStore: appStore, tabId: tabId, isExtended: true)
            case .space:
                NewSpaceRoute(appStore: appStore, tabId: tabId, isExtended: true)
            case .tables:
                TableFactory.rootExtendedView(for: appStore.tableRoot, tabId: tabId)
                    .environment(appStore.tableRoot)
            case .weathers:
                NewWeatherRoute(appStore: appStore, tabId: tabId, isExtended: true)
        }
    }
}
