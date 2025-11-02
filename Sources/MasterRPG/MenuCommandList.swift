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
    let appModel: AppStore

    var body: some Commands {
        if appModel.hasDatabase {
            Group {
                Group {
                    AdventureCommands(root: appModel.adventureRoot)
                    ValueCommands(root: appModel.valueRoot)
                    PdfCommands(root: appModel.pdfRoot)
                    TableCommands(root: appModel.tableRoot)
                    MapCommands(root: appModel.mapRoot)
                }
                Group {
                    AudioCommands(root: appModel.audioRoot)
                    DiceCommands(root: appModel.diceRoot)
                    PhotoCommands(root: appModel.photoRoot)

                    SpaceCommands(root: appModel.spaceRoot, navigator: appModel.navigator)

                    WeatherCommands(root: appModel.weatherRoot)
                }
            }
        }
    }
}

#endif
