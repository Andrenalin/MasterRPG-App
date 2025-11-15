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
        let data = appModel
        AppDependencyManager.shared.add(dependency: data)
        let navigator = appModel.navigator
        AppDependencyManager.shared.add(dependency: navigator)
//        
//        let adventureRootModel = appModel.adventureRoot
//        AppDependencyManager.shared.add(dependency: adventureRootModel)
        let audioRootModel = appModel.audioRoot
        AppDependencyManager.shared.add(dependency: audioRootModel)
//        let characterRootModel = appModel.characterRoot
//        AppDependencyManager.shared.add(dependency: characterRootModel)
        let diceRootModel = appModel.diceRoot
        AppDependencyManager.shared.add(dependency: diceRootModel)
//        let generatorRootModel = appModel.generatorRoot
//        AppDependencyManager.shared.add(dependency: generatorRootModel)
//        let mapRootModel = appModel.mapRoot
//        AppDependencyManager.shared.add(dependency: mapRootModel)
        let pdfRootModel = appModel.pdfRoot
        AppDependencyManager.shared.add(dependency: pdfRootModel)
        let photoRootModel = appModel.photoRoot
        AppDependencyManager.shared.add(dependency: photoRootModel)
        let spaceRootModel = appModel.spaceRoot
        AppDependencyManager.shared.add(dependency: spaceRootModel)
//        let tableRootModel = appModel.tableRoot
//        AppDependencyManager.shared.add(dependency: tableRootModel)
        let weatherRootModel = appModel.weatherRoot
        AppDependencyManager.shared.add(dependency: weatherRootModel)
    }

    @State private var appModel: AppStore = AppStore.shared
    
    var body: some Scene {
        BaseWindow("Game", id: WindowIdentifier.game.rawValue) {
            InitialRootView(appModel: appModel, editorOnly: false)
#if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
#endif
                .modifier(UserSettingsViewModifier(appModel: appModel))
                .setAppSizeMode()
        }
        .commands {
            MenuMainCommand(appModel: appModel)
        }
#if os(macOS)
        .keyboardShortcut("G", modifiers: [.command, .shift, .option])
#endif
        
#if os(macOS)
        Window("Editor", id: WindowIdentifier.editor.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                RootView(appModel: appModel, editorOnly: true)
                    .environment(appModel.optionKeyDownModel)
                    .environment(appModel.settingsModel)
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
        OldWindowLinkList(appModel: appModel)
        
        OldWindowLinkAltList(appModel: appModel)
        
        WindowViewerList(appModel: appModel)
        WindowLinkList(appModel: appModel)
#endif
        
#if os(macOS)
        OldWindowMacList(appModel: appModel)
#endif
        
#if os(macOS) || os(visionOS)
        OldWindowMacVisionList(appModel: appModel)
#endif
        
#if os(visionOS)
        OldWindowVisionList(appModel: appModel)
#endif
    }
}
