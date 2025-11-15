// @copyright André Trettin

import AndrenalinKit
import CoreExternalRPG
import RPGAdventures
import RoleGameKit
import RPGGame
import SwiftUI
import RPGMaps
import RPGValues
import RPGAudios
import RPGPdfs
import RPGPhotos
import RPGSpaces

@MainActor
struct RootView: View {
    let appModel: AppStore
    let editorOnly: Bool

    @Environment(\.locale) private var locale: Locale
    
    @State private var showFirstLunchAlert = false
    @State private var showFirstDataAlert = false

    var body: some View {
        let _ = Self._printChanges()

        Group {
#if os(macOS)
            if editorOnly {
                TabRootView(appModel: appModel, editorOnly: editorOnly)
            } else {
                appModel.gameRoot.viewController.gameWindow {
                    EmptyView()
                }
            }
#elseif os(tvOS)
            appModel.gameRoot.viewController.gameWindow {
                appModel.gameRoot.viewController.gameTabItem()
            }
#else
            appModel.gameRoot.viewController.gameWindow {
                TabRootView(appModel: appModel, editorOnly: editorOnly)
            }
#endif
        }
        .setWideMode()
        .accentColor(.blue)
        .tint(.blue)
        .environmentSetUp(appModel)
        .environment(\.gameModus, appModel.settingsModel.gameModus)
        .environment(\.mapActions, appModel.mapRoot.mapActions)
        .environment(\.networkActions, appModel.gameRoot.networkActions())
        .environment(\.routeActions, appModel.routeActions)
        .environment(\.sharingControlActions, appModel.gameRoot.sharingControlActions)
        .environment(\.sharingFeatureActions, appModel.gameRoot.sharingFeatureActions)
        .environment(\.showGameActions, appModel.settingsModel.showGameActions)
        .environment(\.valueActions, appModel.valueRoot.valueActions)
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
            
            try? await appModel.audioRoot.itemDataCleanup()
            try? await appModel.pdfRoot.itemDataCleanup()
            try? await appModel.spaceRoot.itemDataCleanup()
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
    RootView(appModel: .preview, editorOnly: false)
}

#Preview("Editor") {
    RootView(appModel: .preview, editorOnly: true)
}
