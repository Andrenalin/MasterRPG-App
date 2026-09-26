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
    /// App-level (aggregate) phase: `.background` only once every scene is in the background.
    @Environment(\.scenePhase) private var scenePhase
    
    init() {
        MasterRPGTips.configure()
        // Off-main so the one-time iCloud/App Group container resolution doesn't
        // land on the main thread during early app/window setup. See §5.19.
        Task.detached(priority: .utility) {
            await FileManager.prewarmCloudUrls()
        }
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
        let ruleRootModel = appModel.ruleRoot
        AppDependencyManager.shared.add(dependency: ruleRootModel)
        let spaceRootModel = appModel.spaceRoot
        AppDependencyManager.shared.add(dependency: spaceRootModel)
        let tableRootModel = appModel.tableRoot
        AppDependencyManager.shared.add(dependency: tableRootModel)
        let weatherRootModel = appModel.weatherRoot
        AppDependencyManager.shared.add(dependency: weatherRootModel)

        let generatorRootModel = appModel.generatorRoot
        AppDependencyManager.shared.add(dependency: generatorRootModel)

        // Registered synchronously: `init` already runs on the main actor, and a
        // background intent racing an unstructured Task could otherwise find no
        // starter registered yet and skip waiting entirely. See CODE_AUDIT_17 §3.3.
        DatabaseReadiness.configure {
            data.startDatabaseForBackgroundWork()
        }

#if !os(tvOS)
        let appIntentAppModel = data
        MasterRPGShortcuts.updateAppShortcutParameters()
        Task { @MainActor in
            AppIntentContentInvalidator.configure(
                refreshShortcutParameters: {
                    MasterRPGShortcuts.updateAppShortcutParameters()
                },
                reindexContent: {
                    await MasterRPGSpotlightIndexer.reindexAll(appModel: appIntentAppModel)
                }
            )
            AppIntentContentInvalidator.invalidate()
        }
#endif
        PerformanceTrace.event("AppInitialized")
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
                .gameWindowActivityAssociation(root: appModel.gameRoot, sceneId: SceneId.game.rawValue)
        }
        .commands {
            MenuMainCommand(appModel: appModel)
        }
#if os(macOS)
        .keyboardShortcut("G", modifiers: [.command, .shift, .option])
#endif
#if os(iOS) || os(visionOS)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .background {
                appDelegate.beginBackgroundFlush()
            }
        }
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
