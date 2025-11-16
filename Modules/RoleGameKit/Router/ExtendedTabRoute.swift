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

#if !os(tvOS)
import GeneratorRPG
#endif

public enum ExtendedTabRoute: String, Hashable, Codable {
    case audios
    case dice
    case generator
    case maps
    case pdfs
    case photos
    case space
    case tables
    case weathers
    case settings

    public init(networkModule: NetworkModules) {
        switch networkModule {
            case .audio: self = .audios
            case .dice: self = .dice
            case .generator: self = .generator
            case .map: self = .maps
            case .pdf: self = .pdfs
            case .photo: self = .photos
            case .space: self = .space
            case .table: self = .tables
            case .weather: self = .weathers
            default: self = .settings
        }
    }
    
    public var module: NetworkModules {
        switch self {
            case .audios: .audio
            case .dice: .dice
            case .maps: .map
            case .generator: .generator
            case .pdfs: .pdf
            case .photos: .photo
            case .space: .space
            case .tables: .table
            case .weathers: .weather
            case .settings: .setting
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
        [.pdfs, .tables, .maps, .generator, .photos, .audios, .space, .weathers, .dice, .settings]
    }
}

struct ExtendedTabRouteDestionationView: View {
    let route: ExtendedTabRoute
    let tabId = KnownRoutes.mainTabId

    @Environment(AppStore.self) private var appModel

    var body: some View {
        switch route {
            case .audios:
                AudioFactory.rootView()
            case .dice:
                DiceFactory.rootView()
            case .generator:
#if os(tvOS)
            EmptyView()
#else
            GeneratorRootFactory.rootView()
#endif
            case .maps:
                NewMapRoute(appModel: appModel, tabId: tabId, isExtended: true)
            case .pdfs:
                PdfFactory.rootView()
            case .photos:
                PhotoFactory.rootView()
            case .space:
                SpaceFactory.rootView()
            case .tables:
                NewTableRoute(appModel: appModel, tabId: tabId, isExtended: true)
            case .weathers:
                WeatherRootFactory.rootView()
        case .settings:
            SettingsView(store: appModel)
        }
    }
}
