// @copyright André Trettin

import CoreRPG
import CoreSpotlight
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
    
    /// - Parameter handlesExternalEvents: Whether this view's scene receives continued activities
    ///   (Handoff, Spotlight taps). `false` for scenes that are not windows, such as the macOS
    ///   `MenuBarExtra`: SwiftUI logs an "Invalid Configuration" fault for `onContinueUserActivity` there.
    func appSettingsSetUp(_ appModel: AppModel, handlesExternalEvents: Bool = true) -> some View {
        modifier(AppSettingSetUpViewModifier(appModel: appModel, handlesExternalEvents: handlesExternalEvents))
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
            .task {
                // `appModel` is the app-wide singleton, so the handler may hold it strongly.
                MasterRPGTips.importCampaignHandler = {
                    appModel.presentImportScreen()
                }
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
            .environment(\.isGamePlayer, appModel.gameRoot.isGamePlayer)
            .environment(\.quickDiceSlots, appModel.gameRoot.quickDiceSlots)
            .environment(\.generateMapAction, appModel.gameRoot.generateMapAction)
            .environment(\.sharingControlActions, appModel.gameRoot.sharingControlActions)
            .environment(\.sharingFeatureActions, appModel.gameRoot.sharingFeatureActions)
#if os(visionOS)
            .environment(\.isSpaceSharePlayActive, appModel.gameRoot.isSharePlayActive)
#endif
    }
}

struct AppSettingSetUpViewModifier: ViewModifier {
    let appModel: AppModel
    var handlesExternalEvents = true

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
            .modifier(PersistenceIssueBannerViewModifier(center: .shared))
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
                .modifier(ExternalEventModifier(appModel: appModel, isEnabled: handlesExternalEvents))
    }
}

/// Routes continued activities (own Handoff activity, Spotlight taps) into the app, unless disabled.
private struct ExternalEventModifier: ViewModifier {
    let appModel: AppModel
    let isEnabled: Bool

    @ViewBuilder
    func body(content: Content) -> some View {
        if isEnabled {
            content
                .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                    appModel.continueActivity(userActivity)
                }
#if !os(tvOS)
                .onContinueUserActivity(CSSearchableItemActionType) { userActivity in
                    appModel.continueActivity(userActivity)
                }
#endif
        } else {
            content
        }
    }
}
