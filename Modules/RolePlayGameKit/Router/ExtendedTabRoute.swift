// @copyright André Trettin


import CoreRPG
import SwiftUI

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
        [.pdfs, .tables, .maps, .photos, .audios, .space, .weathers, .dice, .settings]
    }
    
    static var limitedTabs: [ExtendedTabRoute] {
        [.tables, .maps, .photos, .audios, .space, .weathers, .dice]
    }
}
