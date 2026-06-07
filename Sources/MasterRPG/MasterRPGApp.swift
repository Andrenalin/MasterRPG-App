// @copyright André Trettin

import AppIntents
import CoreRPG
import GameRPG
import GroupActivities
import RolePlayGameKit
import SwiftUI
import os.log


#if os(macOS)
typealias BaseWindow = Window
#else
typealias BaseWindow = WindowGroup
#endif

@main
struct MasterRPGApp: App {
#if os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor private var appDelegate: IosAppDelegate
#endif
#if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: MacAppDelegate
#endif
    
    init() {
#if !os(tvOS)
        // Register custom RealityKit components
        RealityKitInit.registerRealityKitComponents()
#endif

        let data = appModel
        AppDependencyManager.shared.add(dependency: data)
        let navigator = appModel.navigator
        AppDependencyManager.shared.add(dependency: navigator)
        
        let adventureRootModel = appModel.adventureRoot
        AppDependencyManager.shared.add(dependency: adventureRootModel)
        let audioRootModel = appModel.audioRoot
        AppDependencyManager.shared.add(dependency: audioRootModel)
        let characterRootModel = appModel.characterRoot
        AppDependencyManager.shared.add(dependency: characterRootModel)
        let diceRootModel = appModel.diceRoot
        AppDependencyManager.shared.add(dependency: diceRootModel)
        
        let mapRootModel = appModel.mapRoot
        AppDependencyManager.shared.add(dependency: mapRootModel)
        let pdfRootModel = appModel.pdfRoot
        AppDependencyManager.shared.add(dependency: pdfRootModel)
        let photoRootModel = appModel.photoRoot
        AppDependencyManager.shared.add(dependency: photoRootModel)
        let spaceRootModel = appModel.spaceRoot
        AppDependencyManager.shared.add(dependency: spaceRootModel)
        let tableRootModel = appModel.tableRoot
        AppDependencyManager.shared.add(dependency: tableRootModel)
        let weatherRootModel = appModel.weatherRoot
        AppDependencyManager.shared.add(dependency: weatherRootModel)

        let generatorRootModel = appModel.generatorRoot
        AppDependencyManager.shared.add(dependency: generatorRootModel)
    }

    private let appModel: AppModel = AppModel.shared
    
    // MARK: - User Activity Handling
    
    var body: some Scene {
        BaseWindow("Game", id: SceneId.game.rawValue) {
            appModel.appNavigationModel.initialRouteType
                .onNavigationRoute(WindowRouter(appModel: appModel, role: .game))
                .onNavigationOpenURL(RootURLHandler(appModel: appModel, role: .game))
                .navigationRoot(appModel.gameNavigator)
                .sceneTracker(for: SceneId.game)
#if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
#endif
                .environmentSetUp(appModel)
                .appSettingsSetUp(appModel)
            //                .groupActivityAssociation(.primary(SceneId.game.rawValue))


        }
        .commands {
            MenuMainCommand(appModel: appModel)
        }
#if os(macOS)
        .keyboardShortcut("G", modifiers: [.command, .shift, .option])
#endif
        
        // Editor Window - moved from WindowViewerList for better multi-window support
        BaseWindow("Editor", id: SceneId.editor.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                AppModeRouteType.editor
                    .frame(minWidth: 1000, minHeight: 600)
            }
            .onNavigationRoute(WindowRouter(appModel: appModel, role: .editor))
            .onNavigationOpenURL(RootURLHandler(appModel: appModel, role: .editor))
            .navigationRoot(appModel.editorNavigator)
            .sceneTracker(for: SceneId.editor)
            .environmentSetUp(appModel)
            .appSettingsSetUp(appModel)
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacementAll(.leading(SceneId.game.rawValue))
        .restorationBehaviorAll(.disabledOnlyVisionOS)
#if os(visionOS)
        .defaultLaunchBehavior(.suppressed)
#endif
#if os(macOS)
        .keyboardShortcut("E", modifiers: [.command, .shift, .option])
#endif
                
#if !os(tvOS)
        WindowViewerList(appModel: appModel)
        WindowLinkList(appModel: appModel)
        WindowUtilityList(appModel: appModel)
#endif
        
#if os(macOS)
        WindowMacList(appModel: appModel)
#endif
        
#if os(visionOS)
        WindowVisionList(appModel: appModel)
#endif
    }
}
