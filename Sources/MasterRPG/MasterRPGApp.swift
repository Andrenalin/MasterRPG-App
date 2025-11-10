// @copyright André Trettin

import AndrenalinKit
import AppIntents
import RoleGameKit
import SwiftUI
import os.log

@main
struct MasterRPGApp: App {
#if os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor private var appDelegate: IosAppDelegate
#endif
#if os(macOS)
    @NSApplicationDelegateAdaptor private var appDelegate: MacAppDelegate
#endif
    
    init() {
        let data = appStore
        AppDependencyManager.shared.add(dependency: data)
        let navigator = appStore.navigator
        AppDependencyManager.shared.add(dependency: navigator)
//        
//        let adventureRootModel = appModel.adventureRoot
//        AppDependencyManager.shared.add(dependency: adventureRootModel)
        let audioRootModel = appStore.audioRoot
        AppDependencyManager.shared.add(dependency: audioRootModel)
//        let characterRootModel = appModel.characterRoot
//        AppDependencyManager.shared.add(dependency: characterRootModel)
//        let diceRootModel = appModel.diceRoot
//        AppDependencyManager.shared.add(dependency: diceRootModel)
//        let generatorRootModel = appModel.generatorRoot
//        AppDependencyManager.shared.add(dependency: generatorRootModel)
//        let mapRootModel = appModel.mapRoot
//        AppDependencyManager.shared.add(dependency: mapRootModel)
//        let pdfRootModel = appModel.pdfRoot
//        AppDependencyManager.shared.add(dependency: pdfRootModel)
//        let photoRootModel = appModel.photoRoot
//        AppDependencyManager.shared.add(dependency: photoRootModel)
        let spaceRootModel = appStore.spaceRoot
        AppDependencyManager.shared.add(dependency: spaceRootModel)
//        let tableRootModel = appModel.tableRoot
//        AppDependencyManager.shared.add(dependency: tableRootModel)
//        let weatherRootModel = appModel.weatherRoot
//        AppDependencyManager.shared.add(dependency: weatherRootModel)
    }

    @State private var appStore: AppStore = AppStore.shared
    
    var body: some Scene {
        BaseWindow("Game", id: WindowIdentifier.game.rawValue) {
            InitialRootView(appStore: appStore, editorOnly: false)
#if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
#endif
                .modifier(UserSettingsViewModifier(appStore: appStore))
                .setAppSizeMode()
        }
        .commands {
            MenuMainCommand(appModel: appStore)
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
            }
        }
        .keyboardShortcut("E", modifiers: [.command, .shift, .option])
        
//        MenuBarExtra() {
//            MenuBarView(audioRoot: appModel.audioRoot)
//        } label: {
//            Label("MasterRPG", systemImage: "music.note.list")
//        }
//        .menuBarExtraStyle(.window)
#endif
        
#if !os(tvOS)
        OldWindowLinkList(appStore: appStore)
        
        OldWindowLinkAltList(appStore: appStore)
        
        WindowViewerList(appModel: appStore)
        WindowLinkList(appModel: appStore)
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
