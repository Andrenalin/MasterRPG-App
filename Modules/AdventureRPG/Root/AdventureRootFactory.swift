// @copyright André Trettin

import AudioRPG
import CharacterRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

import CoreRPG
import SwiftData
import SwiftUI

@MainActor
public struct AdventureRootFactory {
    public static func rootModel(modelContext: ModelContext, audioRoot: AudioRootModel, characterRoot: CharacterRootModel, diceRoot: DiceRootModel, mapRoot: MapRootModel, pdfRoot: PdfRootModel, photoRoot: PhotoRootModel, spaceRoot: SpaceRootModel, tableRoot: TableRootModel, weatherRoot: WeatherRootModel) -> AdventureRootModel {
        AdventureRootModel(modelContext: modelContext, audioRoot: audioRoot, characterRoot: characterRoot, diceRoot: diceRoot, mapRoot: mapRoot, pdfRoot: pdfRoot, photoRoot: photoRoot, spaceRoot: spaceRoot, tableRoot: tableRoot, weatherRoot: weatherRoot)
    }

    public static func rootView() -> some View {
        AdventureRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: AdventureRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
