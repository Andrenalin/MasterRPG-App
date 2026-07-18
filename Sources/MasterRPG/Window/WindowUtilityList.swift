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
                    GeneratorAdventureWindowContent(appModel: appModel, selection: selection)
                }
                .sceneTracker(for: SceneId.generateAdventure)
                .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .adventure))
                .environment(appModel.scenesManager)
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.below(SceneId.game.rawValue))
            .restorationBehaviorAll(.disabled)

            WindowGroup("Map Editor", id: SceneId.mapEditor.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.mapRoot.viewController.mapEditWindow(root: appModel.mapRoot)
                        .sceneTracker(for: SceneId.mapEditor)
                        .modifier(
                            WindowViewerSetUpViewModifier(
                                model: appModel,
                                module: .map,
                                showsWindowToolbarBackground: true
                            )
                        )
#if os(macOS)
                        .toolbarBackground(.windowBackground, for: .windowToolbar)
                        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
#endif
                }
                .environment(appModel.scenesManager)
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.below(SceneId.game.rawValue))
            .restorationBehaviorAll(.disabled)
            
            WindowGroup("Map Tile Editor", id: SceneId.mapTileEditor.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.mapRoot.viewController.mapEditWindow(root: appModel.mapRoot, isTileEditor: true)
                        .sceneTracker(for: SceneId.mapTileEditor)
                        .modifier(
                            WindowViewerSetUpViewModifier(
                                model: appModel,
                                module: .map,
                                showsWindowToolbarBackground: true
                            )
                        )
#if os(macOS)
                        .toolbarBackground(.windowBackground, for: .windowToolbar)
                        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
#endif
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

            BaseWindow("Battle Round", id: SceneId.battleRound.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    GameFactory.battleRoundView(root: appModel.gameRoot)
#if os(macOS)
                        .frame(
                            minWidth: 620,
                            idealWidth: 760,
                            minHeight: 520,
                            idealHeight: 760
                        )
#endif
                        .sceneTracker(for: SceneId.battleRound)
                        .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .map))
                }
                .environment(appModel.scenesManager)
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.trailing(SceneId.game.rawValue))
            .restorationBehaviorAll(.disabled)
#if os(macOS) || os(visionOS)
            .defaultLaunchBehavior(.suppressed)
#endif

#if os(macOS) || os(visionOS)
            BaseWindow("Game Statistics", id: SceneId.gameStatistics.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    ManagedNavigationStack(name: String(localized: "Game Statistics", bundle: .main)) {
                        GameFactory.statisticsView(root: appModel.gameRoot)
                    }
#if os(macOS)
                    .frame(
                        minWidth: 900,
                        idealWidth: 1_000,
                        minHeight: 600,
                        idealHeight: 720
                    )
#endif
                    .sceneTracker(for: SceneId.gameStatistics)
                    .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .game))
                }
                .environment(appModel.scenesManager)
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.trailing(SceneId.game.rawValue))
            .restorationBehaviorAll(.disabled)
            .defaultLaunchBehavior(.suppressed)
#endif
            
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
            .restorationBehaviorAll(.disabledOnlyVisionOS)
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
