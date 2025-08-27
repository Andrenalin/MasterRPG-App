//
//  Master3RPGApp.swift
//  Master3RPG
//
//  Created by Andre Trettin on 02.07.25.
//

import AppIntents
import CoreRPG
import CoreExternalRPG
import RolePlayGameKit
import SwiftUI
import SwiftData

@main
struct Master3RPGApp: App {
    @Environment(\.openURL) private var openURL

    @State private var appModel = AppModel()
    
    init() {
        let data = appModel
        AppDependencyManager.shared.add(dependency: data)
        let navigator = appModel.navigator
        AppDependencyManager.shared.add(dependency: navigator)

        let audioRootModel = appModel.audioRoot
        AppDependencyManager.shared.add(dependency: audioRootModel)
        let diceRootModel = appModel.diceRoot
        AppDependencyManager.shared.add(dependency: diceRootModel)
        let pdfRootModel = appModel.pdfRoot
        AppDependencyManager.shared.add(dependency: pdfRootModel)
        let photoRootModel = appModel.photoRoot
        AppDependencyManager.shared.add(dependency: photoRootModel)
        let spaceRootModel = appModel.spaceRoot
        AppDependencyManager.shared.add(dependency: spaceRootModel)
        let weatherRootModel = appModel.weatherRoot
        AppDependencyManager.shared.add(dependency: weatherRootModel)
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
#if os(macOS)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
                .toolbar(removing: .title)
#endif
                .environment(appModel)
                .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
                    handle(userActivity: userActivity)
                }
        }
        .commands {
#if os(macOS)
            AboutPanelCommand(title: "Master RPG", credits: "Many thanks to my long running test party: Karsten, Roman and Timo.")
            ImportFromDevicesCommands()
#endif
            SidebarCommands()
            TextEditingCommands()
            TextFormattingCommands()

            MenuCommandList(appModel: appModel)
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
        WindowList(appModel: appModel)
            .modelContainer(appModel.modelContainer)
        WindowLinkList(appModel: appModel)
            .modelContainer(appModel.modelContainer)
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
