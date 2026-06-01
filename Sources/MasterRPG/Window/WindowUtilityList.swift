// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI

import AdventureRPG
import MapRPG
import GameRPG

struct WindowUtilityList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
            WindowGroup("Generator Adventure", id: SceneId.generateAdventure.rawValue, for: WindowItemSelection.self) { $selection in
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.adventureRoot.viewController.generatorView(root: appModel.adventureRoot, selection: selection ?? WindowItemSelection(itemId: UUID()))
                        .sceneTracker(for: SceneId.generateAdventure)
                        .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .adventure))
                }
                .environment(appModel.scenesManager)
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.below(SceneId.game.rawValue))
            .restorationBehaviorAll(.disabled)

            WindowGroup("Map Edit Viewer", id: SceneId.mapEditor.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.mapRoot.viewController.mapEditWindow(root: appModel.mapRoot)
                        .sceneTracker(for: SceneId.mapEditor)
                        .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .map))
                }
                .environment(appModel.scenesManager)
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.below(SceneId.game.rawValue))
            .restorationBehaviorAll(.disabled)

            BaseWindow("Logs", id: SceneId.logs.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.gameRoot.viewController.logWindow()
                        .sceneTracker(for: SceneId.logs)
                        .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .game))
                }
                .environment(appModel.scenesManager)
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.above(SceneId.game.rawValue))
            .restorationBehaviorAll(.disabled)
            
            BaseWindow("Search", id: SceneId.search.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    NavigationSplitView {
                        GameFactory.rootSearchView(root: appModel.gameRoot, navigator: appModel.navigator(for: .search))
                    } detail: {
                        GameFactory.detailSearchView(root: appModel.gameRoot, navigator: appModel.navigator(for: .search))
                    }
                    .frame(minWidth: 1000, minHeight: 600)
                }
#if os(macOS)
                .onNavigationRoute(WindowRouter(appModel: appModel, role: .search))
                .onNavigationOpenURL(RootURLHandler(appModel: appModel, role: .search))
                .navigationRoot(appModel.searchNavigator)
#endif
                .sceneTracker(for: SceneId.search)
                .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .search))
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.trailing(SceneId.game.rawValue))
            .restorationBehaviorAll(.disabled)
#if os(macOS) || os(visionOS)
            .defaultLaunchBehavior(.suppressed)
#endif
#if os(macOS)
            .keyboardShortcut("S", modifiers: [.command, .shift, .option])
#endif
        }
        .defaultSize(CGSize(width: 600, height: 800))
    }
}

#endif
