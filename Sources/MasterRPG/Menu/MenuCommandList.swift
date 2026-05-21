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
                    AdventureCommands(root: appModel.adventureRoot, routeActions: routeActions)
                    CharacterCommands(root: appModel.characterRoot, routeActions: routeActions)
                    PdfCommands(root: appModel.pdfRoot, routeActions: routeActions)
                    TableCommands(root: appModel.tableRoot, routeActions: routeActions)
                    MapCommands(root: appModel.mapRoot, routeActions: routeActions)
                }
                Group {
                    AudioCommands(root: appModel.audioRoot, routeActions: routeActions)
                    DiceCommands(root: appModel.diceRoot, routeActions: routeActions)
                    PhotoCommands(root: appModel.photoRoot, routeActions: routeActions)
                    SpaceCommands(root: appModel.spaceRoot, routeActions: routeActions)
                    WeatherCommands(root: appModel.weatherRoot, routeActions: routeActions)
                }
            }
        }
    }
}

#endif
