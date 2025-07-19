// @copyright André Trettin

import AndrenalinKit
import RoleGameKit
import SwiftData
import SwiftUI
import os.log

@main
struct MasterRPGApp: App {
    @State private var databaseModel = DataBaseModel(useCloudKit: AppStore.shared.settingsModel.useCloudKit, currentActor: .mainApp)
    @State private var appStore: AppStore = AppStore.shared

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.openURL) private var openURL
    
#if os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor private var appDelegate: IosAppDelegate
#endif
#if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: MacAppDelegate
#endif

    var body: some Scene {
        BaseWindow("Game", id: WindowIdentifier.game.rawValue) {
            InitialRootView(databaseModel: databaseModel, appStore: appStore, editorOnly: false)
#if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
#endif
                .environment(appStore.windowStateModel)
                .modelContainer(appStore.modelContainer)
                .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                    handle(userActivity: userActivity)
                }                
                .task(id: scenePhase) {
                    guard scenePhase == .active else { return }
//                    await appStore.inAppController.fetchActiveTransactions()
                }
//            #if os(visionOS)
//              This is causing issues that the windows will not be resued.
//                .handlesExternalEvents(preferring: [RPGActivity.activityIdentifier], allowing: [RPGActivity.activityIdentifier])
//            #endif
        }
        .commands {
#if os(macOS)
            AboutPanelCommand(title: "Master RPG", credits: "Many thanks to my long running test party: Karsten, Roman and Timo.")
            ImportFromDevicesCommands()
#endif
            SidebarCommands()
            TextEditingCommands()
            TextFormattingCommands()
            
            MenuCommandList(appStore: appStore)
        }
#if os(macOS)
        .keyboardShortcut("G", modifiers: [.command, .shift, .option])
#endif

#if os(macOS)
        Window("Editor", id: WindowIdentifier.editor.rawValue) {
            DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                RootView(appStore: appStore, editorOnly: true)
                    .environment(appStore.optionKeyDownModel)
                    .environment(appStore.settingsModel)
                    .frame(minWidth: 600, minHeight: 400)
                    .modelContainer(appStore.sharedModelContainer)
            }
        }
        .keyboardShortcut("E", modifiers: [.command, .shift, .option])
#endif

#if !os(tvOS)
        WindowLinkList(appStore: appStore)
        
        WindowLinkAltList(appStore: appStore)
#endif
        
#if os(macOS)
        WindowMacList(appStore: appStore)
#endif

#if os(macOS) || os(visionOS)
        WindowMacVisionList(appStore: appStore)
#endif
        
#if os(visionOS)
        WindowVisionList(appStore: appStore)
#endif
    }
    
    func handle(userActivity: NSUserActivity) {
        // SIRI & Search
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return }
        let childId = UserActivity.childId(from: userActivity)
        //let command: String? = UserActivity.command(from: userActivity)
        let child = childId != nil ? "/\(childId?.uuidString ?? "")" : ""
        let url = URL(string: "\(URL.appScheme)://\(module.token)/0/\(itemId)\(child)")!
        openURL(url)
    }
}
