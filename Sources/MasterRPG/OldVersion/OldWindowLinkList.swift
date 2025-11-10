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
    let appStore: AppStore

    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        BaseWindow("Logs", id: WindowIdentifier.logs.rawValue) {
            DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                appStore.gameRoot.viewController.logWindow()
            }
            .handlesExternalEvents(preferring: [], allowing: [])
        }
        .defaultSizeAll(CGSize(width: 1200, height: 600))
        .defaultWindowPlacementAll(.above(WindowIdentifier.game.rawValue))

        Group {
            BaseWindow("\(NetworkModules.adventure.title) Link", id: NetworkModules.adventure.linkWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.adventureRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .onDisappear {
                    appStore.windowStateModel.openWindowState[.adventure] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appStore.windowPlacement(for: .adventure))
#if os(macOS)
            .keyboardShortcut("1", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.value.title) Link", id: NetworkModules.value.linkWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.valueRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .onDisappear {
                    appStore.windowStateModel.openWindowState[.value] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appStore.windowPlacement(for: .value))
#if os(macOS)
            .keyboardShortcut("2", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.pdf.title) Link", id: NetworkModules.pdf.linkWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.pdfRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .onDisappear {
                    appStore.windowStateModel.openWindowState[.pdf] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appStore.windowPlacement(for: .pdf))
#if os(macOS)
            .keyboardShortcut("3", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.table.title) Link", id: NetworkModules.table.linkWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.tableRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                        .environment(\.valueActions, appStore.valueRoot.valueActions)
                }
                .onDisappear {
                    appStore.windowStateModel.openWindowState[.table] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appStore.windowPlacement(for: .table))
#if os(macOS)
            .keyboardShortcut("4", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.map.title) Link", id: NetworkModules.map.linkWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.mapRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .onDisappear {
                    appStore.windowStateModel.openWindowState[.map] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appStore.windowPlacement(for: .map))
#if os(macOS)
            .keyboardShortcut("5", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.dice.title) Link", id: NetworkModules.dice.linkWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.diceRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .onDisappear {
                    appStore.windowStateModel.openWindowState[.dice] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appStore.windowPlacement(for: .dice))
#if os(macOS)
            .keyboardShortcut("7", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.photo.title) Link", id: NetworkModules.photo.linkWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.photoRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                        .environment(\.mapActions, appStore.mapRoot.mapActions)
                }
                .onDisappear {
                    appStore.windowStateModel.openWindowState[.photo] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appStore.windowPlacement(for: .photo))
#if os(macOS)
            .keyboardShortcut("8", modifiers: [.command, .option])
#endif

            BaseWindow("\(NetworkModules.weather.title) Link", id: NetworkModules.weather.linkWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.weatherRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .onDisappear {
                    appStore.windowStateModel.openWindowState[.weather] = false
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            .defaultWindowPlacementAll(appStore.windowPlacement(for: .weather))
#if os(macOS)
            .keyboardShortcut("0", modifiers: [.command, .option])
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
    let appStore: AppStore
    
    var body: some Scene {
        Group {
            WindowGroup("\(NetworkModules.adventure.title) Link", id: NetworkModules.adventure.linkAltWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.adventureRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }

            WindowGroup("\(NetworkModules.value.title) Link", id: NetworkModules.value.linkAltWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.valueRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            
            WindowGroup("\(NetworkModules.pdf.title) Link", id: NetworkModules.pdf.linkAltWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.pdfRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }

            WindowGroup("\(NetworkModules.table.title) Link", id: NetworkModules.table.linkAltWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.tableRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                        .environment(\.valueActions, appStore.valueRoot.valueActions)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }

            WindowGroup("\(NetworkModules.map.title) Link", id: NetworkModules.map.linkAltWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.mapRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }

            WindowGroup("\(NetworkModules.dice.title) Link", id: NetworkModules.dice.linkAltWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.diceRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            
            WindowGroup("\(NetworkModules.photo.title) Link", id: NetworkModules.photo.linkAltWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.photoRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
                        .environment(\.mapActions, appStore.mapRoot.mapActions)
                }
                .handlesExternalEvents(preferring: [], allowing: [])
            }
            
            WindowGroup("\(NetworkModules.weather.title) Link", id: NetworkModules.weather.linkAltWindowId) {
                DataBaseAppStoreAvailable(appStore: appStore) { appStore in
                    appStore.weatherRoot.viewController.linkWindow()
                        .modifier(WindowListSetUpViewModifier(appStore: appStore))
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
    let appStore: AppStore
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .accentColor(.teal)
#if os(macOS)
            .frame(minWidth: 250, minHeight: 250)
#endif
#if os(iOS)
            .environment(\.colorScheme, appStore.settingsModel.appColorScheme.colorScheme(for: colorScheme))
#endif
            .environment(\.gameModus, appStore.settingsModel.gameModus)
            .environment(\.networkActions, appStore.gameRoot.networkActions())
            .environment(\.sharingControlActions, appStore.gameRoot.sharingControlActions)
            .environment(\.sharingFeatureActions, appStore.gameRoot.sharingFeatureActions)
            .environment(\.showGame, appStore.settingsModel.showGame)
            .environment(appStore.optionKeyDownModel)
            .environment(appStore.deviceRotationModel)
            .tint(.teal)
    }
}

#endif
