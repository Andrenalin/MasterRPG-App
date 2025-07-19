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
        [.pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice]
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
                .environment(appModel.photoRoot)
            case .space:
            SpaceRootFactory.rootView(withoutNavigation: true)
                .environment(appModel.spaceRoot)
            case .tables:
            RootListView(rootRoute: .tables)
            case .weathers:
            RootListView(rootRoute: .weathers)
        }
    }
}
