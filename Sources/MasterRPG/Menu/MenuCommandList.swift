// @copyright André Trettin

#if !os(tvOS)

import AdventureRPG
import CoreRPG
import DiceRPG
import GeneratorRPG
import RolePlayGameKit
import AudioRPG
import GameRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
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
                    AdventureCommands(root: appModel.adventureRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    CharacterCommands(root: appModel.characterRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    PdfCommands(root: appModel.pdfRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    RuleCommands(root: appModel.ruleRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    TableCommands(root: appModel.tableRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    MapCommands(root: appModel.mapRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                }
                Group {
                    AudioCommands(root: appModel.audioRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    DiceCommands(root: appModel.diceRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    PhotoCommands(root: appModel.photoRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    SpaceCommands(root: appModel.spaceRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    WeatherCommands(root: appModel.weatherRoot, scenesManager: appModel.scenesManager, routeActions: routeActions)
                    // No GeneratorCommands on purpose: the generator has no list of its own.
                    // See CODE_AUDIT_Since_3.0.1 §5.3.
                }
                PasteboardCommands(roots: [
                    appModel.adventureRoot, appModel.characterRoot, appModel.pdfRoot, appModel.ruleRoot,
                    appModel.tableRoot, appModel.mapRoot, appModel.audioRoot, appModel.diceRoot,
                    appModel.photoRoot, appModel.spaceRoot, appModel.weatherRoot
                ])
            }
        }
    }
}

#endif
