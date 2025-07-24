// @copyright André Trettin

import CoreExternalRPG
import CoreRPG
import PhotoRPG
import SpaceRPG
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
    case settings
    
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
                self = .settings
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
            case .settings: .setting
        }
    }
}

extension ExtendedTabRoute {
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
        [.pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice, .settings]
    }
}

struct ExtendedTabRouteDestionationView: View {
    let route: ExtendedTabRoute
    
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        switch route {
            case .audios:
                RootListView(rootRoute: .audios)
            case .dice:
                RootListView(rootRoute: .dice)
            case .maps:
                RootListView(rootRoute: .maps)
            case .pdfs:
                RootListView(rootRoute: .pdfs)
            case .photos:
                PhotoRootFactory.rootView(withoutNavigation: true)
            case .space:
                SpaceRootFactory.rootView(withoutNavigation: true)
            case .tables:
                RootListView(rootRoute: .tables)
            case .weathers:
                RootListView(rootRoute: .weathers)
            case .settings:
                Text("Cooming soon")
        }
    }
}
