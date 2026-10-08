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
import RuleRPG
import SpaceRPG
import TableRPG
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
        ruleRoot: RuleRootModel,
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
            ruleRoot: ruleRoot,
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
        if let itemId = root.navigationModel.selectedItemId {
            ItemSplitDetailRouteRootView(root: root.rootController, route: AdventureRoute.detail(itemId))
        } else {
            SplitContentUnavailableView(module: root.configurable.module)
        }
    }
}
