// @copyright André Trettin

import AppIntents
import CoreRPG
import CoreExternalRPG
import RolePlayGameKit
import SwiftUI
import SwiftData

@main
struct Master3RPGApp: App {
    @State private var appModel = AppModel()
    
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

    var body: some Scene {
        WindowGroup("Game", id: WindowIdentifier.game.rawValue) {
            AppRootView(appModel: appModel)
#if os(macOS)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
#endif
                .modifier(UserSettingsViewModifier(appModel: appModel))
                .setAppSizeMode()
        }
        .commands {
            MenuMainCommand(appModel: appModel)
        }
        .modelContainer(appModel.modelContainer)
        

#if os(macOS)
        MenuBarExtra() {
            MenuBarView(audioRoot: appModel.audioRoot)
        } label: {
            Label("MasterRPG", systemImage: "music.note.list")
        }
        .menuBarExtraStyle(.window)
#endif
        
#if !os(tvOS)
        WindowViewerList(appModel: appModel)
            .modelContainer(appModel.modelContainer)
        WindowLinkList(appModel: appModel)
            .modelContainer(appModel.modelContainer)
#endif

    }
}
