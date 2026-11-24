// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI

import AdventureRPG
import CharacterRPG
import MapRPG
import GameRPG
import TableRPG

struct WindowUtilityList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
#if os(macOS) || os(visionOS)
            WindowGroup(
                "Table Generator",
                id: SceneId.tableGenerator.rawValue,
                for: WindowItemSelection.self
            ) { $selection in
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    TableGeneratorWindowContent(
                        appModel: appModel,
                        selection: selection
                    )
                    .sceneTracker(for: SceneId.tableGenerator)
                    .modifier(
                        WindowViewerSetUpViewModifier(
                            model: appModel,
                            module: .table,
                            showsWindowToolbarBackground: true
                        )
                    )
                }
                .environment(appModel.scenesManager)
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.below(NetworkModules.table.linkWindowId))
            .restorationBehaviorAll(.disabled)
            .defaultLaunchBehavior(.suppressed)
            .defaultSize(CGSize(width: 600, height: 800))
#endif

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


            BaseWindow("Battle Round", id: SceneId.battleRound.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    GameFactory.battleRoundView(root: appModel.gameRoot)
#if os(macOS)
                        // Ideal size and least height only. The least width is
                        // the battle view's own (its list plus, when open, its
                        // inspector), so there is one minimum per axis here
                        // instead of this frame and the shared window one below.
                        .frame(
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
#if os(visionOS)
            .defaultSize(CGSize(width: 600, height: 800))
#endif
#if os(macOS) || os(visionOS)
            .defaultLaunchBehavior(.suppressed)
#endif

#if os(visionOS)
            BaseWindow("Table Players", id: SceneId.tablePlayers.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    GameFactory.tablePlayersView(root: appModel.gameRoot)
                        .sceneTracker(for: SceneId.tablePlayers)
                        .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .game))
                }
                .environment(appModel.scenesManager)
                .environment(appModel)
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(.trailing(SceneId.game.rawValue))
            .restorationBehaviorAll(.disabled)
            .defaultSize(CGSize(width: 600, height: 800))
            .defaultLaunchBehavior(.suppressed)
#endif

#if os(macOS) || os(visionOS)
            BaseWindow("Game Statistics", id: SceneId.gameStatistics.rawValue) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    ManagedNavigationStack(name: String(localized: "Game Statistics", bundle: .main)) {
                        GameFactory.statisticsView(root: appModel.gameRoot)
                    }
                    .sceneTracker(for: SceneId.gameStatistics)
                    .modifier(WindowViewerSetUpViewModifier(model: appModel, module: .game))
                }
                .environment(appModel.scenesManager)
                .environment(appModel)
#if os(macOS)
                    .frame(
                        minWidth: 700,
                        idealWidth: 900,
                        minHeight: 480,
                        idealHeight: 680
                    )
#endif
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
    }
}

#if os(macOS) || os(visionOS)
private struct TableGeneratorWindowContent: View {
    let appModel: AppModel
    let selection: WindowItemSelection?

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if let itemId = selection?.itemId,
               let generator = appModel.tableRoot.generationControllable {
                generator.generationView(
                    itemId: itemId,
                    dismissAction: { dismiss() }
                )
            } else {
                ContentUnavailableView {
                    Label {
                        Text("Table Unavailable", bundle: .main)
                    } icon: {
                        Image(systemName: "tablecells")
                    }
                } description: {
                    Text(
                        "Choose a table to generate.",
                        bundle: .main
                    )
                }
            }
        }
        .environment(appModel.appGameStateModel)
        .environment(\.networkActions, appModel.gameRoot.networkActions)
        .environment(
            \.sharingControlActions,
            appModel.gameRoot.sharingControlActions
        )
        .environment(
            \.itemGenerationResultAction,
            ItemGenerationResultAction(id: .object(ObjectIdentifier(appModel))) { summary in
                appModel.generatedValueEntry = ValueEntryModel(
                    generationSummary: summary
                )
            }
        )
    }
}
#endif

#endif
