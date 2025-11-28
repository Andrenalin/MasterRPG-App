// @copyright André Trettin

import AndrenalinKit
import DiceRPG
import AudioRPG
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftData
import SwiftUI
import WeatherRPG
import CoreExternalRPG

public enum AdventureFactory {
    @MainActor public static func root(
        container: ModelContainer,
        audioRoot: AudioRootModel,
        diceRoot: DiceRootModel,
        mapRoot: MapRootModel,
        pdfRoot: PdfRootModel,
        photoRoot: PhotoRootModel,
        spaceRoot: SpaceRootModel,
        tableRoot: TableRootModel,
        valueRoot: CharacterRootModel,
        weatherRoot: WeatherRootModel
    ) -> AdventureRootModel {
        AdventureRootModel(
            container: container,
            audioRoot: audioRoot,
            diceRoot: diceRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            valueRoot: valueRoot,
            weatherRoot: weatherRoot
        )
    }

    @MainActor public static func rootView() -> some View {
        AdventureRootView()
    }
        
    @MainActor @ViewBuilder public static func detailView(root: AdventureRootModel) -> some View {
        ItemSplitDetailRootView(root: root.rootController)
    }
}
