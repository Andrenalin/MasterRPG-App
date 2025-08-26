// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import RolePlayGameKit
import SwiftUI
import AudioRPG
import DiceRPG
import PdfRPG
import PhotoRPG
import SpaceRPG

struct WindowLinkList: Scene {
    let appModel: AppModel
    
    var body: some Scene {
        Group {
            WindowGroup("\(NetworkModules.pdf.title) Link", id: NetworkModules.pdf.linkWindowId) {
                appModel.pdfRoot.viewController.linkWindow()
                    .environment(appModel.pdfRoot)
                    .accentColor(.teal)
                    .tint(.teal)
                    .frame(minWidth: 350, minHeight: 400)
                    .onDisappear {
                        appModel.windowStateModel.openWindowState[.pdf] = false
                    }
                    .handlesExternalEvents(preferring: [], allowing: [])
#if os(macOS)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(appModel.windowPlacement(for: .pdf))
#if os(macOS)
            .keyboardShortcut("3", modifiers: [.command, .option])
#endif

            WindowGroup("\(NetworkModules.audio.title) Link", id: NetworkModules.audio.linkWindowId) {
                appModel.audioRoot.viewController.linkWindow()
                    .environment(appModel.audioRoot)
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

            WindowGroup("\(NetworkModules.dice.title) Link", id: NetworkModules.dice.linkWindowId) {
                appModel.diceRoot.viewController.linkWindow()
                    .environment(appModel.diceRoot)
                    .accentColor(.teal)
                    .tint(.teal)
                    .frame(minWidth: 350, minHeight: 400)
                    .onDisappear {
                        appModel.windowStateModel.openWindowState[.dice] = false
                    }
                    .handlesExternalEvents(preferring: [], allowing: [])
#if os(macOS)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(appModel.windowPlacement(for: .dice))
#if os(macOS)
            .keyboardShortcut("7", modifiers: [.command, .option])
#endif

            WindowGroup("\(NetworkModules.photo.title) Link", id: NetworkModules.photo.linkWindowId) {
                appModel.photoRoot.viewController.linkWindow()
                    .environment(appModel.photoRoot)
                    .accentColor(.teal)
                    .tint(.teal)
                    .frame(minWidth: 350, minHeight: 400)
                    .onDisappear {
                        appModel.windowStateModel.openWindowState[.photo] = false
                    }
                    .handlesExternalEvents(preferring: [], allowing: [])
#if os(macOS)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(appModel.windowPlacement(for: .photo))
#if os(macOS)
            .keyboardShortcut("8", modifiers: [.command, .option])
#endif
            WindowGroup("\(NetworkModules.space.title) Link", id: NetworkModules.space.linkWindowId) {
                appModel.spaceRoot.viewController.linkWindow()
                    .environment(appModel.spaceRoot)
                    .accentColor(.teal)
                    .tint(.teal)
                    .frame(minWidth: 350, minHeight: 400)
                    .onDisappear {
                        appModel.windowStateModel.openWindowState[.space] = false
                    }
                    .handlesExternalEvents(preferring: [], allowing: [])
#if os(macOS)
                    .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
#endif
            }
            .windowResizability(.contentSize)
            .defaultWindowPlacementAll(appModel.windowPlacement(for: .space))
#if os(macOS)
            .keyboardShortcut("9", modifiers: [.command, .option])
#endif
        }
        .defaultSize(CGSize(width: 400, height: 800))
    }
}

#endif
