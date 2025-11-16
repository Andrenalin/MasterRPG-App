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
        container: ModelContainer,
        adventureRoot: AdventureRoot,
        audioRoot: AudioRoot,
        characterRoot: ValueRoot,
        diceRoot: DiceRootModel,
        mapRoot: MapRoot,
        pdfRoot: PdfRoot,
        photoRoot: PhotoRoot,
        spaceRoot: SpaceRoot,
        tableRoot: TableRoot,
        weatherRoot: WeatherRootModel
    ) -> GeneratorRootModel {
        GeneratorRootModel(
            container: container,
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
