// @copyright André Trettin

import AndrenalinKit
import RPGAdventures
import RoleGameKit
import SwiftUI
import RPGGame
import RPGValues
import RPGPdfs
import RPGTables
import RPGAudios
import RPGPhotos
import RPGDie
import RPGMaps
import RPGSpaces
import RPGWeathers

#if os(macOS)
typealias BaseWindow = Window
#else
typealias BaseWindow = WindowGroup
#endif

#if !os(tvOS)

struct OldWindowLinkList: Scene {
    let appModel: AppStore

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        BaseWindow("Logs", id: WindowIdentifier.logs.rawValue) {
            DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                appModel.gameRoot.viewController.logWindow()
            }
            .handlesExternalEvents(preferring: [], allowing: [])
        }
        .defaultSizeAll(CGSize(width: 1200, height: 600))
        .defaultWindowPlacementAll(.above(WindowIdentifier.game.rawValue))

        Group {
            BaseWindow("\(NetworkModules.adventure.title) Link", id: NetworkModules.adventure.linkWindowId) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.adventureRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appModel: appModel))
                }
                .onDisappear {
                    appModel.windowStateModel.openWindowState[.adventure] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appModel.windowPlacement(for: .adventure))
#if os(macOS)
            .keyboardShortcut("1", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.value.title) Link", id: NetworkModules.value.linkWindowId) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.valueRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appModel: appModel))
                }
                .onDisappear {
                    appModel.windowStateModel.openWindowState[.value] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appModel.windowPlacement(for: .value))
#if os(macOS)
            .keyboardShortcut("2", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.table.title) Link", id: NetworkModules.table.linkWindowId) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.tableRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appModel: appModel))
                        .environment(\.valueActions, appModel.valueRoot.valueActions)
                }
                .onDisappear {
                    appModel.windowStateModel.openWindowState[.table] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appModel.windowPlacement(for: .table))
#if os(macOS)
            .keyboardShortcut("4", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.map.title) Link", id: NetworkModules.map.linkWindowId) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.mapRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appModel: appModel))
                }
                .onDisappear {
                    appModel.windowStateModel.openWindowState[.map] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appModel.windowPlacement(for: .map))
#if os(macOS)
            .keyboardShortcut("5", modifiers: [.command, .option])
#endif

        }
        .defaultSizeAll(CGSize(width: 400, height: 800))
#if os(macOS)
        .defaultPosition(.topTrailing)
        .windowStyle(.automatic)
#endif
    }
}

struct OldWindowLinkAltList: Scene {
    let appModel: AppStore
    
    var body: some Scene {
        Group {
            WindowGroup("\(NetworkModules.adventure.title) Link", id: NetworkModules.adventure.linkAltWindowId) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.adventureRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appModel: appModel))
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }

            WindowGroup("\(NetworkModules.value.title) Link", id: NetworkModules.value.linkAltWindowId) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.valueRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appModel: appModel))
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            
            WindowGroup("\(NetworkModules.table.title) Link", id: NetworkModules.table.linkAltWindowId) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.tableRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appModel: appModel))
                        .environment(\.valueActions, appModel.valueRoot.valueActions)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }

            WindowGroup("\(NetworkModules.map.title) Link", id: NetworkModules.map.linkAltWindowId) {
                DataBaseAppStoreAvailable(appModel: appModel) { appModel in
                    appModel.mapRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appModel: appModel))
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
        }
        .defaultSizeAll(CGSize(width: 400, height: 800))
#if os(macOS)
        .defaultPosition(.topLeading)
        .windowStyle(.hiddenTitleBar)
#endif
    }
}

struct WindowListSetUpViewModifier: ViewModifier {
    let appModel: AppStore
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .accentColor(.teal)
#if os(macOS)
            .frame(minWidth: 250, minHeight: 250)
#endif
#if os(iOS)
            .environment(\.colorScheme, appModel.settingsModel.appColorScheme.colorScheme(for: colorScheme))
#endif
            .environment(\.gameModus, appModel.settingsModel.gameModus)
            .environment(\.networkActions, appModel.gameRoot.networkActions())
            .environment(\.sharingControlActions, appModel.gameRoot.sharingControlActions)
            .environment(\.sharingFeatureActions, appModel.gameRoot.sharingFeatureActions)
            .environment(\.showGame, appModel.settingsModel.showGame)
            .environment(appModel.optionKeyDownModel)
            .environment(appModel.deviceRotationModel)
            .tint(.teal)
    }
}

#endif
