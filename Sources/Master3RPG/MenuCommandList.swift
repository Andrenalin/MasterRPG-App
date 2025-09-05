// @copyright André Trettin

#if !os(tvOS)

import RolePlayGameKit
import AudioRPG
import CharacterRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG
import SwiftUI

struct MenuCommandList: Commands {
    let appModel: AppModel

    var body: some Commands {
        Group {
            //        Group {
            //            AdventureCommands(root: appStore.adventureRoot)
            CharacterCommands(root: appModel.characterRoot, navigator: appModel.navigator)
            PdfCommands(root: appModel.pdfRoot, navigator: appModel.navigator)
            TableCommands(root: appModel.tableRoot, navigator: appModel.navigator)
            //        }
            //
            //        MapCommands(root: appStore.mapRoot)

            Group {
                AudioCommands(root: appModel.audioRoot, navigator: appModel.navigator)
                DiceCommands(root: appModel.diceRoot, navigator: appModel.navigator)
                PhotoCommands(root: appModel.photoRoot, navigator: appModel.navigator)
                SpaceCommands(root: appModel.spaceRoot, navigator: appModel.navigator)
            }

            WeatherCommands(root: appModel.weatherRoot, navigator: appModel.navigator)
        }
    }
}

#endif
