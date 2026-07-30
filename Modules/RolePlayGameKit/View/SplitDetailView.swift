// @copyright André Trettin

import CoreRPG
import AdventureRPG
import AudioRPG
import DiceRPG
import GameRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import SwiftUI

#if !os(tvOS)
import GeneratorRPG
#endif

struct SplitDetailView: View {
    let module: NetworkModules

    @Environment(AppModel.self) private var appModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        switch module {
        case .adventure:
            AdventureFactory.detailView(root: appModel.adventureRoot)
        case .audio:
            AudioFactory.detailView(root: appModel.audioRoot)
        case .dice:
            DiceFactory.detailView(root: appModel.diceRoot)
        case .game:
            EmptyView()
        case .generator:
#if os(tvOS)
            EmptyView()
#else
            GeneratorRootFactory.detailView(root: appModel.generatorRoot)
#endif
        case .map:
            MapRootFactory.detailView(root: appModel.mapRoot)
        case .pdf:
            PdfFactory.detailView(root: appModel.pdfRoot)
        case .photo:
            PhotoFactory.detailView(root: appModel.photoRoot)
        case .rule:
            RuleFactory.detailView(root: appModel.ruleRoot)
        case .search: GameFactory.detailSearchView(root: appModel.gameRoot, navigator: appModel.navigator(for: .search))
        case .space:
            SpaceFactory.detailView(root: appModel.spaceRoot)
        case .table:
            TableFactory.detailView(root: appModel.tableRoot)
        case .value:
            CharacterRootFactory.detailView(root: appModel.characterRoot)
        case .weather:
            WeatherRootFactory.detailView(root: appModel.weatherRoot)
        case .setting:
            EmptyView()
        default:
            ContentUnavailableView {
                Label {
                    Text(verbatim: module.title)
                } icon: {
                    Image(systemName: module.icon)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}


#Preview {
    SplitDetailView(module: .adventure)
        .environment(AppModel())
}
