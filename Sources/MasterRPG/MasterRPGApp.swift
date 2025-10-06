// @copyright André Trettin

import AndrenalinKit
import AppIntents
import RolePlayGameKit
import RoleGameKit
import SwiftData
import SwiftUI
import os.log

@main
struct MasterRPGApp: App {
    // NEW
    @State private var appModel = AppModel()
    
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
        
        let adventureRootModel = appModel.adventureRoot
        AppDependencyManager.shared.add(dependency: adventureRootModel)
        let audioRootModel = appModel.audioRoot
        AppDependencyManager.shared.add(dependency: audioRootModel)
        let characterRootModel = appModel.characterRoot
        AppDependencyManager.shared.add(dependency: characterRootModel)
        let diceRootModel = appModel.diceRoot
        AppDependencyManager.shared.add(dependency: diceRootModel)
        let generatorRootModel = appModel.generatorRoot
        AppDependencyManager.shared.add(dependency: generatorRootModel)
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
    }
    
    // OLD
    @State private var appStore: AppStore = AppStore.shared
    
    var body: some Scene {
        BaseWindow("Game", id: WindowIdentifier.game.rawValue) {
            Group {
                if appStore.isNewUICode {
                    AppRootView(appModel: appModel)
                } else {
                    InitialRootView(appStore: appStore, editorOnly: false)
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
            if appStore.isNewUICode {
                MenuMainCommand(appModel: appModel)
            } else {
                OldMenuMainCommand(appStore: appStore)
            }
        }
        .modelContainer(appModel.modelContainer)
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
        
        MenuBarExtra() {
            MenuBarView(audioRoot: appModel.audioRoot)
        } label: {
            Label("MasterRPG", systemImage: "music.note.list")
        }
        .menuBarExtraStyle(.window)
#endif
        
#if !os(tvOS)
        OldWindowLinkList(appStore: appStore)
        
        OldWindowLinkAltList(appStore: appStore)
        
        WindowViewerList(appModel: appModel)
            .modelContainer(appModel.modelContainer)
        WindowLinkList(appModel: appModel)
            .modelContainer(appModel.modelContainer)
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
