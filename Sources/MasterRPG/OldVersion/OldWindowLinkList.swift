// @copyright André Trettin

import AndrenalinKit
import AdventureRPG
import RolePlayGameKit
import SwiftUI
import GameRPG
import CharacterRPG
import PdfRPG
import TableRPG
import AudioRPG
import PhotoRPG
import DiceRPG
import MapRPG
import SpaceRPG
import WeatherRPG

#if os(macOS)
typealias BaseWindow = Window
#else
typealias BaseWindow = WindowGroup
#endif

#if !os(tvOS)

struct OldWindowLinkList: Scene {
    let appModel: AppModel

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        BaseWindow("Logs", id: WindowIdentifier.logs.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                appModel.gameRoot.viewController.logWindow()
            }
            .handlesExternalEvents(preferring: [], allowing: [])
        }
        .defaultSizeAll(CGSize(width: 1200, height: 600))
        .defaultWindowPlacementAll(.above(WindowIdentifier.game.rawValue))
    }
}

#endif
