// @copyright André Trettin

import AndrenalinKit
import RolePlayGameKit
import RoleGameKit
import SwiftData
import SwiftUI
import os.log

@main
struct MasterRPGApp: App {
    @State private var appStore: AppStore = AppStore.shared
    
    @State private var appModel = AppModel()
    
#if os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor private var appDelegate: IosAppDelegate
#endif
#if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: MacAppDelegate
#endif

    var body: some Scene {
        BaseWindow("Game", id: WindowIdentifier.game.rawValue) {
            Group {
                if appStore.isNewUICode {
                    AppRootView(appModel: appModel)
#if os(macOS)
                        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                        .toolbar(removing: .title)
#endif
                        .modifier(UserSettingsViewModifier(appModel: appModel))
                } else {
                    InitialRootView(appStore: appStore, editorOnly: false)
#if os(macOS)
                        .frame(minWidth: 800, minHeight: 600)
#endif
                        .environment(appStore.windowStateModel)
                        .modelContainer(appStore.modelContainer)
                    //                .task(id: scenePhase) {
                    //                    guard scenePhase == .active else { return }
                    //                    await appStore.inAppController.fetchActiveTransactions()
                    //                }
                }
            }
            .onChange(of: appStore.isNewUICode) {
                appModel.isNewUICode <=> appStore.isNewUICode
            }
            .onChange(of: appModel.isNewUICode) {
                appStore.isNewUICode <=> appModel.isNewUICode
            }
            }
            .commands {
#if os(macOS)
                OldAboutPanelCommand(title: "Master RPG", credits: "Many thanks to my long running test party: Karsten, Roman and Timo.")
                ImportFromDevicesCommands()
#endif
                SidebarCommands()
                TextEditingCommands()
                TextFormattingCommands()
                
                OldMenuCommandList(appStore: appStore)
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
                        .modelContainer(appStore.modelContainer)
                }
            }
            .keyboardShortcut("E", modifiers: [.command, .shift, .option])
#endif
            
#if !os(tvOS)
            OldWindowLinkList(appStore: appStore)
            
            OldWindowLinkAltList(appStore: appStore)
#endif
            
#if os(macOS)
            OldWindowMacList(appStore: appStore)
#endif
            
#if os(macOS) || os(visionOS)
            OldWindowMacVisionList(appStore: appStore)
#endif
            
#if os(visionOS)
            OldWindowVisionList(appStore: appStore)
#endif
    }
}
