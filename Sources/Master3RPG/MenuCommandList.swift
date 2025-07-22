// @copyright André Trettin

#if !os(tvOS)

import RolePlayGameKit
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
            //            PdfCommands(root: appStore.pdfRoot)
            //            TableCommands(root: appStore.tableRoot)
            //        }
            //
            //        MapCommands(root: appStore.mapRoot)

            Group {
                //            AudioCommands(root: appStore.audioRoot)
                //            DiceCommands(root: appStore.diceRoot)
                PhotoCommands(root: appModel.photoRoot, navigator: appModel.navigator)
                //            SpaceCommands(root: appModel.spaceRoot)
            }

            //        WeatherCommands(root: appStore.weatherRoot)
        }
    }
}

#endif
