// @copyright André Trettin

import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
#if !os(tvOS)
import GeneratorRPG
#endif
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import SwiftData
import SwiftUI
import WeatherRPG

public enum AdventureFactory {
    @MainActor public static func root(
        tagController: TagController,
        audioRoot: AudioRootModel,
        diceRoot: DiceRootModel,
        generatorRoot: GeneratorRootModel?,
        mapRoot: MapRootModel,
        pdfRoot: PdfRootModel,
        photoRoot: PhotoRootModel,
        spaceRoot: SpaceRootModel,
        tableRoot: TableRootModel,
        characterRoot: CharacterRootModel,
        weatherRoot: WeatherRootModel
    ) -> AdventureRootModel {
        AdventureRootModel(
            tagController: tagController,
            audioRoot: audioRoot,
            diceRoot: diceRoot,
            generatorRoot: generatorRoot,
            mapRoot: mapRoot,
            pdfRoot: pdfRoot,
            photoRoot: photoRoot,
            spaceRoot: spaceRoot,
            tableRoot: tableRoot,
            characterRoot: characterRoot,
            weatherRoot: weatherRoot
        )
    }
    
    @MainActor public static func rootView() -> some View {
        AdventureRootView()
    }
    
    @MainActor @ViewBuilder public static func detailView(root: AdventureRootModel) -> some View {
        // Extract observable property to break dependency chain
        let selectedItemId = root.navigationModel.selectedItemId

        if let itemId = selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: AdventureRoute.detail(itemId))
        }
    }
}
