// @copyright André Trettin

import CoreRPG
import SwiftUI
import MapRPG
import GameRPG
import CharacterRPG
import os.log

public extension View {
    func environmentSetUp(_ appModel: AppModel) -> some View {
        modifier(AppEnvironmentSetUpViewModifier(appModel: appModel))
    }
    
    func environmentActionSetUp(_ appModel: AppModel) -> some View {
        modifier(AppActionEnvironmentSetUpViewModifier(appModel: appModel))
    }
    
    func appSettingsSetUp(_ appModel: AppModel) -> some View {
        modifier(AppSettingSetUpViewModifier(appModel: appModel))
    }
}

struct AppEnvironmentSetUpViewModifier: ViewModifier {
    let appModel: AppModel

    func body(content: Content) -> some View {
        content
            // Core models
            .environment(appModel)
            .setAppSizeMode()
            .environment(appModel.appGameStateModel)
            .environment(appModel.optionKeyDownModel)
            .environment(appModel.settingsModel)
            .environment(appModel.scenesManager)
            .environment(appModel.appNavigationModel)
        
            // Module roots
            .environment(appModel.adventureRoot)
            .environment(appModel.audioRoot)
            .environment(appModel.characterRoot)
            .environment(appModel.diceRoot)
#if !os(tvOS)
            .environment(appModel.generatorRoot)
#endif
            .environment(appModel.mapRoot)
            .environment(appModel.pdfRoot)
            .environment(appModel.photoRoot)
            .environment(appModel.spaceRoot)
            .environment(appModel.tableRoot)
            .environment(appModel.weatherRoot)
    }
}

struct AppActionEnvironmentSetUpViewModifier: ViewModifier {
    let appModel: AppModel

    func body(content: Content) -> some View {
        content
            .environment(\.mapActions, appModel.mapRoot.mapActions)
            .environment(\.routeActions, appModel.routeActions)
            .environment(\.valueActions, appModel.characterRoot.valueActions)
    }
}

struct AppSettingSetUpViewModifier: ViewModifier {
    let appModel: AppModel
    
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) var dismissWindow
#if os(visionOS)
    @Environment(\.openImmersiveSpace) var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) var dismissImmersiveSpace
#endif
    
    func body(content: Content) -> some View {
        content
            .modifier(UserSettingsViewModifier(appModel: appModel))
#if os(visionOS)
                .onAppear {
                    appModel.scenesManager.setActions(
                        openWindow: openWindow,
                        dismissWindow: dismissWindow,
                        openImmersiveSpace: openImmersiveSpace,
                        dismissImmersiveSpace: dismissImmersiveSpace
                    )
                }
#else
                .onAppear {
                    appModel.scenesManager.setActions(
                        openWindow: openWindow,
                        dismissWindow: dismissWindow
                    )
                }
#endif
                .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                    handleUserActivity(userActivity)
                }
    }
    
    /// Handles incoming NSUserActivity from Spotlight, Siri, Handoff, etc.
    /// This handler works across all windows and platforms (iOS, iPadOS, macOS, visionOS)
    private func handleUserActivity(_ userActivity: NSUserActivity) {
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return }
        let childId = UserActivity.childId(from: userActivity)

        Logger.bootStrap.info("Handling user activity for module: \(module.rawValue), itemId: \(itemId)")

        appModel.routeToModule(module, itemId: itemId, entryId: childId)
    }
}
