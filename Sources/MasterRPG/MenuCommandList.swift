// @copyright André Trettin

#if !os(tvOS)

import RPGAdventures
import DiceRPG
import RoleGameKit
import AudioRPG
import RPGGame
import MapRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import SwiftUI
import WeatherRPG

struct MenuCommandList: Commands {
    let appModel: AppModel

    var body: some Commands {
        if appModel.hasDatabase {
            Group {
                Group {
                    AdventureCommands(root: appModel.adventureRoot, navigator: appModel.navigator)
                    CharacterCommands(root: appModel.valueRoot, navigator: appModel.navigator)
                    PdfCommands(root: appModel.pdfRoot, navigator: appModel.navigator)
                    TableCommands(root: appModel.tableRoot, navigator: appModel.navigator)
                    MapCommands(root: appModel.mapRoot, navigator: appModel.navigator)
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
