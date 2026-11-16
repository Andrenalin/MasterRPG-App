// @copyright André Trettin

import AdventureRPG
import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import GameRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import SwiftUI
import TableRPG
import WeatherRPG

#if !os(tvOS)
import GeneratorRPG
#endif

struct RouteDestinationView: View {
    let route: RootRoute
    @Environment(AppModel.self) private var appModel

    var body: some View {
        Group {
            switch route {
            case .adventures:
                AdventureFactory.rootView()
            case .audios:
                AudioFactory.rootView()
            case .dice:
                DiceFactory.rootView()
            case .editors:
                ExtendedTabBar()
            case .game:
                GameSetupDestinationView()
            case .generator:
#if os(tvOS)
                EmptyView()
#else
                GeneratorRootFactory.rootView()
#endif
            case .maps:
                MapRootFactory.rootView()
            case .pdfs:
                PdfFactory.rootView()
            case .photos:
                PhotoFactory.rootView()
            case .rules:
                RuleFactory.rootView()
            case .space:
                SpaceFactory.rootView()
            case .settings:
                ManagedNavigationStack {
                    SettingsView(store: appModel)
                }
            case .tables:
                TableFactory.rootView()
            case .values:
                CharacterRootFactory.rootView()
            case .weathers:
                WeatherFactory.rootView()
            case .search:
                GameFactory.rootSearchView(root: appModel.gameRoot, navigator: appModel.navigator(for: .search))
            }
        }
        .moduleTint(route.module)
    }
}

#Preview("Settings destination") {
    RouteDestinationView(route: .settings)
        .environment(AppModel())
}
