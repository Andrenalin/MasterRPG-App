// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
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

struct WindowLinkList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
            windowGroup(model: appModel, module: .adventure, key: "1", content: appModel.adventureRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.adventureRoot.linkSelectionModel))

            windowGroup(model: appModel, module: .value, key: "2", content: appModel.characterRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.characterRoot.linkSelectionModel))

            windowGroup(model: appModel, module: .pdf, key: "3", content: appModel.pdfRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.pdfRoot.itemSelectionModel))

            windowGroup(model: appModel, module: .table, key: "4", content: appModel.tableRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.tableRoot.linkSelectionModel))

            windowGroup(model: appModel, module: .map, key: "5", content: appModel.mapRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.mapRoot.linkSelectionModel))

            windowGroup(model: appModel, module: .audio, key: "6", content: appModel.audioRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.audioRoot.linkSelectionModel))

            windowGroup(model: appModel, module: .dice, key: "7", content: appModel.diceRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.diceRoot.linkSelectionModel))

            windowGroup(model: appModel, module: .photo, key: "8", content: appModel.photoRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.photoRoot.linkSelectionModel))

            windowGroup(model: appModel, module: .space, key: "9", content: appModel.spaceRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.spaceRoot.linkSelectionModel))

            windowGroup(model: appModel, module: .weather, key: "0", content: appModel.weatherRoot.viewController.linkListView(type: .window, itemSelectionModel: appModel.weatherRoot.linkSelectionModel))
        }
        .defaultSize(CGSize(width: 400, height: 800))
    }
    
    private func windowGroup<Content: View>(model: AppModel, module: NetworkModules, key: KeyEquivalent, content: Content) -> some Scene {
        WindowGroup("\(module.title) Link", id: module.linkWindowId) {
            DataBaseAppStoreAvailable(appModel: model) { model in
                ManagedNavigationStack(name: module.linkWindowId) {
                    content
                }
                .sceneTracker(for: SceneId.sceneId(for: module))
                .modifier(WindowLinkSetUpViewModifier(model: model, module: module))
            }
            .environment(model.scenesManager)
            .environment(model)
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacementAll(model.windowPlacement(for: module))
        .restorationBehaviorAll(.disabled)
#if os(macOS)
        .keyboardShortcut(key, modifiers: [.command, .option])
#endif
    }
}

struct WindowLinkSetUpViewModifier: ViewModifier {
    let model: AppModel
    let module: NetworkModules
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .resetAppColorScheme()
            .frame(minWidth: 350, minHeight: 400)
            .handlesExternalEvents(preferring: [], allowing: [])
            .tint(module.tint)
            .environmentSetUp(model)
            .environmentActionSetUp(model)
#if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
    }
}

#endif
