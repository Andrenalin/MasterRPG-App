// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI

import AudioRPG
import CharacterRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import TableRPG
import WeatherRPG

struct WindowLinkList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
            windowGroup(model: appModel, module: .value, key: "2", content:                 appModel.characterRoot.viewController.linkWindow(root: appModel.characterRoot))

            windowGroup(model: appModel, module: .pdf, key: "3", content:                 appModel.pdfRoot.viewController.linkWindow(root: appModel.pdfRoot))

            windowGroup(model: appModel, module: .table, key: "4", content:                 appModel.tableRoot.viewController.linkWindow(root: appModel.tableRoot))

            windowGroup(model: appModel, module: .audio, key: "6", content:                 appModel.audioRoot.viewController.linkWindow(root: appModel.audioRoot))

            windowGroup(model: appModel, module: .dice, key: "7", content:                 appModel.diceRoot.viewController.linkWindow(root: appModel.diceRoot))

            windowGroup(model: appModel, module: .photo, key: "8", content:                 appModel.photoRoot.viewController.linkWindow(root: appModel.photoRoot))

            windowGroup(model: appModel, module: .space, key: "9", content:                 appModel.spaceRoot.viewController.linkWindow(root: appModel.spaceRoot))

            windowGroup(model: appModel, module: .weather, key: "0", content:                 appModel.weatherRoot.viewController.linkWindow(root: appModel.weatherRoot))
        }
        .defaultSize(CGSize(width: 400, height: 800))
    }
    
    private func windowGroup<Content: View>(model: AppModel, module: NetworkModules, key: KeyEquivalent, content: Content) -> some Scene {
        WindowGroup("\(module.title) Link", id: module.linkWindowId) {
            content
                .accentColor(.teal)
                .tint(.teal)
                .frame(minWidth: 350, minHeight: 400)
                .onDisappear {
                    model.windowStateModel.openWindowState[module] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
#if os(macOS)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacementAll(model.windowPlacement(for: module))
#if os(macOS)
        .keyboardShortcut(key, modifiers: [.command, .option])
#endif
    }
}

#endif
