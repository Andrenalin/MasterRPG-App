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
            .environment(appModel.searchBarVisibleModel)
            .environment(appModel.optionKeyDownModel)
            .environment(appModel.settingsModel)
            .environment(appModel.scenesManager)
            .environment(appModel.appFocusModel)
            .environment(appModel.appNavigationModel)
            .environment(\.supporterTier, appModel.supporterTier)
        
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
            .environment(appModel.ruleRoot)
            .environment(appModel.spaceRoot)
            .environment(appModel.tableRoot)
            .environment(appModel.weatherRoot)
            .onReceive(
                NotificationCenter.default.publisher(
                    for: MasterRPGTips.importCampaignRequested
                )
            ) { _ in
                appModel.presentImportScreen()
            }
            .task {
                await appModel.inAppController.prepare()
                appModel.inAppController.startObservingTransactionUpdates()
            }
            .onChange(of: appModel.supporterTier, initial: true) { _, supporterTier in
                appModel.gameRoot.updateSupporterTier(supporterTier)
            }
    }
}

struct AppActionEnvironmentSetUpViewModifier: ViewModifier {
    let appModel: AppModel

    func body(content: Content) -> some View {
        content
            .environment(\.mapActions, appModel.mapRoot.mapActions)
            .environment(\.routeActions, appModel.routeActions)
            .environment(\.networkActions, appModel.gameRoot.networkActions)
            .environment(\.sharingControlActions, appModel.gameRoot.sharingControlActions)
            .environment(\.sharingFeatureActions, appModel.gameRoot.sharingFeatureActions)
    }
}

struct AppSettingSetUpViewModifier: ViewModifier {
    let appModel: AppModel

    #if !os(tvOS)
    @Environment(\.openWindow) var openWindow
    @Environment(\.dismissWindow) var dismissWindow
    #endif
#if os(macOS)
    @Environment(\.openSettings) private var openSettings
#endif
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
#elseif os(macOS)
                .onAppear {
                    appModel.scenesManager.setActions(
                        openWindow: openWindow,
                        dismissWindow: dismissWindow
                    )
                    appModel.scenesManager.setOpenSettingsAction(openSettings)
                }
#elseif !os(tvOS)
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

        appModel.routeToModuleWhenReady(module, itemId: itemId, entryId: childId)
    }
}
