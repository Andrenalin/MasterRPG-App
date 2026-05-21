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

    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) var dismissWindow
#if os(visionOS)
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
#endif
    
//#if !os(macOS)
//    @Environment(IosSceneDelegate.self) private var sceneDelegate
//#endif


    @State private var appModel: AppModel = AppModel.shared
    
    // MARK: - User Activity Handling
    
    /// Handles incoming NSUserActivity from Spotlight, Siri, Handoff, etc.
    /// This handler works across all windows and platforms (iOS, iPadOS, macOS, visionOS)
    private func handleUserActivity(_ userActivity: NSUserActivity) {
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return }
        let childId = UserActivity.childId(from: userActivity)

        Logger.bootStrap.info("Handling user activity for module: \(module.rawValue), itemId: \(itemId)")

        appModel.routeToModule(module, itemId: itemId, entryId: childId)
    }
    
    var body: some Scene {
        BaseWindow("Game", id: SceneId.game.rawValue) {
            InitialRootView()
                .onNavigationRoute(WindowRouter(appModel: appModel, role: .game))
                .onNavigationOpenURL(RootURLHandler(appModel: appModel, role: .game))
                .navigationRoot(appModel.gameNavigator)
                .sceneTracker(for: SceneId.game)
                .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                    handleUserActivity(userActivity)
                }
#if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
#endif
                .modifier(UserSettingsViewModifier(appModel: appModel))
                .environmentSetUp(appModel)
#if os(visionOS)
//                .groupActivityAssociation(.primary(SceneId.game.rawValue))
                .onAppear {
                    appModel.sceneManager.setActions(
                        openWindow: openWindow,
                        dismissWindow: dismissWindow,
                        openImmersiveSpace: openImmersiveSpace,
                        dismissImmersiveSpace: dismissImmersiveSpace
                    )
//                    appModel.appNavigationModel.reset(sceneDelegate: sceneDelegate)
                }
#else
                .onAppear {
                    appModel.sceneManager.setActions(
                        openWindow: openWindow,
                        dismissWindow: dismissWindow
                    )
                }
#endif
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
                    .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                        handleUserActivity(userActivity)
                    }
            }
            .onNavigationRoute(WindowRouter(appModel: appModel, role: .editor))
            .onNavigationOpenURL(RootURLHandler(appModel: appModel, role: .editor))
            .navigationRoot(appModel.editorNavigator)
            .setAppSizeMode()
            .sceneTracker(for: SceneId.editor)
            .environmentSetUp(appModel)
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacementAll(.leading(SceneId.game.rawValue))
        .restorationBehaviorAll(.disabled)
#if os(macOS) || os(visionOS)
        .defaultLaunchBehavior(.suppressed)
#endif
#if os(macOS)
        .keyboardShortcut("E", modifiers: [.command, .shift, .option])
#endif
                
#if !os(tvOS)
        WindowViewerList(appModel: appModel)
        WindowLinkList(appModel: appModel)
#endif
        
#if os(macOS)
        WindowMacList(appModel: appModel)
#endif
        
#if os(visionOS)
        WindowVisionList(appModel: appModel)
#endif
    }
}
