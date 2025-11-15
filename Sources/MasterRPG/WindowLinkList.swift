// @copyright André Trettin

#if !os(tvOS)
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

struct WindowLinkList: Scene {
    let appModel: AppStore
    
    var body: some Scene {
        Group {
//            windowGroup(model: appModel, module: .adventure, key: "1", content: appModel.adventureRoot.viewController.linkWindow(root: appModel.adventureRoot))
//
//            windowGroup(model: appModel, module: .value, key: "2", content: appModel.characterRoot.viewController.linkWindow(root: appModel.characterRoot))
//
            windowGroup(model: appModel, module: .pdf, key: "3", content: appModel.pdfRoot.viewController.linkWindow(root: appModel.pdfRoot))

//            windowGroup(model: appModel, module: .table, key: "4", content: appModel.tableRoot.viewController.linkWindow(root: appModel.tableRoot))
//
//            windowGroup(model: appModel, module: .map, key: "5", content: appModel.mapRoot.viewController.linkWindow(root: appModel.mapRoot))
//
            windowGroup(model: appModel, module: .audio, key: "6", content: appModel.audioRoot.viewController.linkWindow(root: appModel.audioRoot))

//            windowGroup(model: appModel, module: .dice, key: "7", content: appModel.diceRoot.viewController.linkWindow(root: appModel.diceRoot))
//
            windowGroup(model: appModel, module: .photo, key: "8", content: appModel.photoRoot.viewController.linkWindow(root: appModel.photoRoot))

            windowGroup(model: appModel, module: .space, key: "9", content: appModel.spaceRoot.viewController.linkWindow(root: appModel.spaceRoot))

//            windowGroup(model: appModel, module: .weather, key: "0", content: appModel.weatherRoot.viewController.linkWindow(root: appModel.weatherRoot))
        }
        .defaultSize(CGSize(width: 400, height: 800))
    }
    
    private func windowGroup<Content: View>(model: AppStore, module: NetworkModules, key: KeyEquivalent, content: Content) -> some Scene {
        WindowGroup("\(module.title) Link", id: module.linkWindowId) {
            content
                .modifier(WindowLinkSetUpViewModifier(model: model, module: module))
        }
        .windowResizability(.contentSize)
        .defaultWindowPlacementAll(model.windowPlacement(for: module))
#if os(macOS)
        .keyboardShortcut(key, modifiers: [.command, .option])
#endif
    }
}

struct WindowLinkSetUpViewModifier: ViewModifier {
    let model: AppStore
    let module: NetworkModules
    
    @Environment(\.colorScheme) private var colorScheme
    
    func body(content: Content) -> some View {
        content
            .frame(minWidth: 350, minHeight: 400)
            .handlesExternalEvents(preferring: [], allowing: [])
            .onDisappear {
                model.windowStateModel.openWindowState[module] = false
            }
            .tint(module.tint)
#if os(iOS)
            .environment(\.colorScheme, model.settingsModel.appColorScheme.colorScheme(for: colorScheme))
#endif
            .environmentSetUp(model)
            .environment(\.gameModus, model.settingsModel.gameModus)
            .environment(\.networkActions, model.gameRoot.networkActions())
            .environment(\.sharingControlActions, model.gameRoot.sharingControlActions)
            .environment(\.sharingFeatureActions, model.gameRoot.sharingFeatureActions)
            .environment(\.showGame, model.settingsModel.showGame)
#if os(macOS)
            .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
    }
}

#endif
