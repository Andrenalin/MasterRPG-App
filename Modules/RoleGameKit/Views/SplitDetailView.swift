// @copyright André Trettin

import AndrenalinKit
import RPGAdventures
import AudioRPG
import DiceRPG
import RPGMaps
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
    @Environment(AppModel.self) private var appModel
    
    var body: some View {
        switch selectedModule {
        case .adventure: AdventureFactory.detailView(root: appModel.adventureRoot)
        case .audio: AudioFactory.detailView(root: appModel.audioRoot)
        case .dice: DiceFactory.detailView(root: appModel.diceRoot)
        case .game: EmptyView()
        case .generator:
#if os(tvOS)
            EmptyView()
#else
            GeneratorRootFactory.detailView(root: appModel.generatorRoot)
#endif
        case .map: MapFactory.detailView(root: appModel.mapRoot)
        case .pdf: PdfFactory.detailView(root: appModel.pdfRoot)
        case .photo: PhotoFactory.detailView(root: appModel.photoRoot)
        case .space: SpaceFactory.detailView(root: appModel.spaceRoot)
        case .table: TableFactory.detailView(root: appModel.tableRoot)
        case .value: CharacterRootFactory.detailView(root: appModel.valueRoot)
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
