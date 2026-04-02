// @copyright André Trettin

import CoreRPG

import AdventureRPG
import RolePlayGameKit
import GameRPG
import SwiftUI
import MapRPG
import CharacterRPG
import AudioRPG
import PdfRPG
import PhotoRPG
import SpaceRPG
import DiceRPG
import TableRPG
import WeatherRPG

@MainActor
struct RootView: View {
    let appModel: AppModel
    var editorOnly: Bool = false
    
    @Environment(\.locale) private var locale: Locale
    
    @State private var showFirstLunchAlert = false
    @State private var showFirstDataAlert = false

    var body: some View {
        Group {
#if os(macOS)
            if editorOnly {
                TabRootView(appModel: appModel)
            } else {
                appModel.gameRoot.viewController.gameWindow {
                    appModel.gameRoot.viewController.gameTabItem()
                }
            }
#elseif os(tvOS)
            appModel.gameRoot.viewController.gameWindow {
                appModel.gameRoot.viewController.gameTabItem()
            }
#else
            appModel.gameRoot.viewController.gameWindow {
                TabRootView(appModel: appModel)
            }
#endif
        }
        .setWideMode()
        .accentColor(.blue)
        .tint(.blue)
        .environmentSetUp(appModel)
        .environmentActionSetUp(appModel)
        .navigationRoot(appModel.navigator)
        .appExitNotifications(handler: appModel.adventureRoot.save)
        .task {
#if os(tvOS)
            try? await Task.sleep(for: .seconds(1))
            if appModel.photoRoot.itemControllable.itemDataModel.items.isEmpty {
                appModel.installExampleData(isGerman: locale.identifier.hasPrefix("de"))
            }
#else
            try? await Task.sleep(for: .seconds(1))
            if appModel.settingsModel.firstLaunch {
                showFirstLunchAlert.toggle()
            }
            try? await Task.sleep(for: .seconds(5))
            
            await appModel.cleanDatabase()
#endif
        }
        .alert("First Launch", isPresented: $showFirstLunchAlert) {
            Button {
                appModel.installExampleData(isGerman: locale.identifier.hasPrefix("de"))
                appModel.settingsModel.firstLaunch = false
                withAnimation { showFirstDataAlert.toggle() }
            } label: {
                Text("Initialize")
            }
            
            Button {
                appModel.settingsModel.firstLaunch = false
            } label: {
                Text("Not now")
            }
        } message: {
            Text("This is the first lunch and there is no data in the database. Do you want to initialize the database with explaination data? No download is required the example data is prebundled.")
        }
        .alert("Explaination Data", isPresented: $showFirstDataAlert) {
            Button {
            } label: {
                Text("Ok")
            }
        } message: {
            Text("The explaination data is saved. You will find the data in the other sections.")
        }
    }
}

#Preview("Game") {
    RootView(appModel: .preview)
}
