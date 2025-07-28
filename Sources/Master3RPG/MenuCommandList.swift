// @copyright André Trettin

#if !os(tvOS)

import RolePlayGameKit
import AudioRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import SwiftUI

struct MenuCommandList: Commands {
    let appModel: AppModel

    var body: some Commands {
        Group {
            //        Group {
            //            AdventureCommands(root: appStore.adventureRoot)
            //            ValueCommands(root: appStore.valueRoot)
            PdfCommands(root: appModel.pdfRoot, navigator: appModel.navigator)
            //            TableCommands(root: appStore.tableRoot)
            //        }
            //
            //        MapCommands(root: appStore.mapRoot)

            Group {
                AudioCommands(root: appModel.audioRoot, navigator: appModel.navigator)
                //            DiceCommands(root: appStore.diceRoot)
                PhotoCommands(root: appModel.photoRoot, navigator: appModel.navigator)
                SpaceCommands(root: appModel.spaceRoot, navigator: appModel.navigator)
            }

            //        WeatherCommands(root: appStore.weatherRoot)
        }
    }
}

#endif
