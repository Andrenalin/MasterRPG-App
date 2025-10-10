// @copyright André Trettin

import CoreRPG
import AdventureRPG
import AudioRPG
import CharacterRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG
import SwiftUI

struct SplitDetailView: View {
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        switch selectedModule {
        case .adventure: AdventureRootFactory.detailView(root: appModel.adventureRoot)
        case .audio: AudioRootFactory.detailView(root: appModel.audioRoot)
        case .dice: DiceRootFactory.detailView(root: appModel.diceRoot)
        case .game: EmptyView()
        case .generator:
            #if os(tvOS)
            EmptyView()
            #else
            GeneratorRootFactory.detailView(root: appModel.generatorRoot)
            #endif
        case .map: MapRootFactory.detailView(root: appModel.mapRoot)
        case .pdf: PdfRootFactory.detailView(root: appModel.pdfRoot)
        case .photo: PhotoRootFactory.detailView(root: appModel.photoRoot)
        case .space: SpaceRootFactory.detailView(root: appModel.spaceRoot)
        case .table: TableRootFactory.detailView(root: appModel.tableRoot)
        case .weather: WeatherRootFactory.detailView(root: appModel.weatherRoot)
        case .setting: EmptyView()
        default:
            ContentUnavailableView(selectedModule.title, image: selectedModule.icon)
        }
    }
    
    var selectedModule: NetworkModules {
        (appModel.selectedModule ?? .game).module
    }
}

#Preview {
    SplitDetailView()
}
