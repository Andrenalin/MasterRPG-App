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
public struct GameRootFactory {
    public static func rootController(
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
    ) -> GameRootController {
        GameRootController(
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

    public static func rootView(root: GameRootController) -> some View {
        GameRootTabItemView(root: root)
    }
}
