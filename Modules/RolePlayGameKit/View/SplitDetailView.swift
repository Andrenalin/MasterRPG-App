// @copyright André Trettin

import CoreRPG
import AdventureRPG
import AudioRPG
import DiceRPG
import GameRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import WeatherRPG
import SwiftUI

#if !os(tvOS)
import GeneratorRPG
#endif

struct SplitDetailView: View {
    let isExtendedRoutes: Bool

    @Environment(AppModel.self) private var appModel

    var body: some View {
        let _ = Self._printChanges()

        switch selectedModule {
        case .adventure:
            AdventureFactory.detailView(root: appModel.adventureRoot)
        case .audio:
            AudioFactory.detailView(
                root: appModel.audioRoot,
                selectedItemId: appModel.audioRoot.navigationModel.selectedItemId
            )
        case .dice:
            DiceFactory.detailView(
                root: appModel.diceRoot,
                selectedItemId: appModel.diceRoot.navigationModel.selectedItemId
            )
        case .game: EmptyView()
        case .generator:
#if os(tvOS)
            EmptyView()
#else
            GeneratorRootFactory.detailView(
                root: appModel.generatorRoot,
                selectedItemId: appModel.generatorRoot.navigationModel.selectedItemId
            )
#endif
        case .map:
            MapRootFactory.detailView(
                root: appModel.mapRoot,
                selectedItemId: appModel.mapRoot.navigationModel.selectedItemId
            )
        case .pdf:
            PdfFactory.detailView(
                root: appModel.pdfRoot,
                selectedItemId: appModel.pdfRoot.navigationModel.selectedItemId
            )
        case .photo:
            PhotoFactory.detailView(
                root: appModel.photoRoot,
                selectedItemId: appModel.photoRoot.navigationModel.selectedItemId
            )
        case .search: GameFactory.detailSearchView(root: appModel.gameRoot, navigator: appModel.navigator)
        case .space:
            SpaceFactory.detailView(
                root: appModel.spaceRoot,
                selectedItemId: appModel.spaceRoot.navigationModel.selectedItemId
            )
        case .table:
            TableFactory.detailView(
                root: appModel.tableRoot,
                selectedItemId: appModel.tableRoot.navigationModel.selectedItemId
            )
        case .value:
            CharacterRootFactory.detailView(
                root: appModel.characterRoot,
                selectedItemId: appModel.characterRoot.navigationModel.selectedItemId
            )
        case .weather:
            WeatherRootFactory.detailView(
                root: appModel.weatherRoot,
                selectedItemId: appModel.weatherRoot.navigationModel.selectedItemId
            )
        case .setting: EmptyView()
        default:
            ContentUnavailableView(selectedModule.title, image: selectedModule.icon)
        }
    }

    var selectedModule: NetworkModules {
        isExtendedRoutes ? (appModel.selectedEditorModule ?? .pdfs).module : (appModel.selectedModule ?? .game).module
    }
}


#Preview {
    SplitDetailView(isExtendedRoutes: false)
}
