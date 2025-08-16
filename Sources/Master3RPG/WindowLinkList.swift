// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI
import AudioRPG

struct WindowLinkList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
            WindowGroup("\(NetworkModules.audio.title) Link", id: NetworkModules.audio.linkWindowId) {
                appModel.audioRoot.viewController.linkWindow()
                    .accentColor(.teal)
                    .tint(.teal)
                    .frame(minWidth: 350, minHeight: 400)
                    .onDisappear {
                        appModel.windowStateModel.openWindowState[.audio] = false
                    }
                .handlesExternalEvents(preferring: [], allowing: [])
#if os(macOS)
                .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(appModel.windowPlacement(for: .audio))
            #if os(macOS)
            .keyboardShortcut("6", modifiers: [.command, .option])
            #endif
        }
        .defaultSize(CGSize(width: 400, height: 800))
    }
}

#endif
