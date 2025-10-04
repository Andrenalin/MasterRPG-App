// @copyright André Trettin

import AdventureRPG
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
public struct GeneratorRootFactory {
    public static func rootModel(
        modelContext: ModelContext,
        adventureRoot: AdventureRootModel,
        audioRoot: AudioRootModel,
        characterRoot: CharacterRootModel,
        diceRoot: DiceRootModel,
        mapRoot: MapRootModel,
        pdfRoot: PdfRootModel,
        photoRoot: PhotoRootModel,
        spaceRoot: SpaceRootModel,
        tableRoot: TableRootModel,
        weatherRoot: WeatherRootModel
    ) -> GeneratorRootModel {
        GeneratorRootModel(
            modelContext: modelContext,
            adventureRoot: adventureRoot,
            audioRoot: audioRoot,
            characterRoot: characterRoot,
            diceRoot: diceRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            weatherRoot: weatherRoot
        )
    }
    
    public static func rootView() -> some View {
        GeneratorRootView()
    }
    
    @ViewBuilder
    public static func detailView(root: GeneratorRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
