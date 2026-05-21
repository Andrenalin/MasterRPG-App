// @copyright André Trettin

#if !os(tvOS)

import AdventureRPG
import CoreRPG
import DiceRPG
import RolePlayGameKit
import AudioRPG
import GameRPG
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
        if appModel.appNavigationModel.initialRouteType == .ready {
            let routeActions = appModel.routeActions
            Group {
                Group {
                    AdventureCommands(root: appModel.adventureRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                    CharacterCommands(root: appModel.characterRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                    PdfCommands(root: appModel.pdfRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                    TableCommands(root: appModel.tableRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                    MapCommands(root: appModel.mapRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                }
                Group {
                    AudioCommands(root: appModel.audioRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                    DiceCommands(root: appModel.diceRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                    PhotoCommands(root: appModel.photoRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                    SpaceCommands(root: appModel.spaceRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                    WeatherCommands(root: appModel.weatherRoot, scenesManager: appModel.sceneManager, routeActions: routeActions)
                }
            }
        }
    }
}

#endif
