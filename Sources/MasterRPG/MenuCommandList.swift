// @copyright André Trettin

#if !os(tvOS)

import RPGAdventures
import RPGDie
import RoleGameKit
import RPGAudios
import RPGGame
import RPGMaps
import RPGPdfs
import RPGPhotos
import RPGSpaces
import RPGTables
import RPGValues
import SwiftUI
import RPGWeathers

struct MenuCommandList: Commands {
    let appModel: AppModel

    var body: some Commands {
        if appModel.hasDatabase {
            Group {
                Group {
                    AdventureCommands(root: appModel.adventureRoot)
                    ValueCommands(root: appModel.valueRoot)
                    PdfCommands(root: appModel.pdfRoot, navigator: appModel.navigator)
                    TableCommands(root: appModel.tableRoot)
                    MapCommands(root: appModel.mapRoot)
                }
                Group {
                    AudioCommands(root: appModel.audioRoot, navigator: appModel.navigator)
                    DiceCommands(root: appModel.diceRoot, navigator: appModel.navigator)
                    PhotoCommands(root: appModel.photoRoot, navigator: appModel.navigator)

                    SpaceCommands(root: appModel.spaceRoot, navigator: appModel.navigator)

                    WeatherCommands(root: appModel.weatherRoot, navigator: appModel.navigator)
                }
            }
        }
    }
}

#endif
