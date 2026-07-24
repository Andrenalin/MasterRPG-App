// @copyright André Trettin

import AudioRPG
import CoreRPG
import DiceRPG
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

struct ExtendedTabRouteDestionationView: View {
    let route: ExtendedTabRoute
    let tabId = KnownRoutes.mainTabId

    @Environment(AppModel.self) private var appModel

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
            MapRootFactory.rootView()
        case .pdfs:
            PdfFactory.rootView()
        case .photos:
            PhotoFactory.rootView()
        case .rules:
            RuleFactory.rootView()
        case .space:
            SpaceFactory.rootView()
        case .tables:
            TableFactory.rootView()
        case .weathers:
            WeatherRootFactory.rootView()
        case .settings:
            SettingsView(store: appModel)
        }
    }
}

#Preview("Settings editor destination") {
    ExtendedTabRouteDestionationView(route: .settings)
        .environment(AppModel())
}
