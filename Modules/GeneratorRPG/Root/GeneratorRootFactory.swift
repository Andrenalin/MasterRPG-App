// @copyright André Trettin

import RPGAdventures
import RPGAudios
import RPGValues
import RPGDie
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGWeathers

import AndrenalinKit
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
