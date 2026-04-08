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

    @State private var appModel: AppModel = AppModel.shared
    
    var body: some Scene {
        BaseWindow("Game", id: WindowIdentifier.game.rawValue) {
            InitialRootView()
#if os(macOS)
                .frame(minWidth: 800, minHeight: 600)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
#endif
                .modifier(UserSettingsViewModifier(appModel: appModel))
                .environmentSetUp(appModel)
#if os(visionOS)
                .groupActivityAssociation(.primary(WindowIdentifier.game.rawValue))
#endif
        }
        .commands {
            MenuMainCommand(appModel: appModel)
        }
#if os(macOS)
        .keyboardShortcut("G", modifiers: [.command, .shift, .option])
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
