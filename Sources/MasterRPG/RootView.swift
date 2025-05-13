// @copyright André Trettin

import AndrenalinKit
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
    let appStore: AppStore
    let editorOnly: Bool

    @Environment(\.locale) private var locale: Locale
    @State private var showFirstLunchAlert = false
    @State private var showFirstDataAlert = false

    var body: some View {
        let _ = Self._printChanges()

        Group {
#if os(macOS)
            if editorOnly {
                TabRootView(appStore: appStore, editorOnly: editorOnly)
            } else {
                appStore.gameRoot.viewController.gameWindow {
                    EmptyView()
                }
            }
#elseif os(tvOS)
            appStore.gameRoot.viewController.gameWindow {
                appStore.gameRoot.viewController.gameTabItem()
            }
#else
            appStore.gameRoot.viewController.gameWindow {
                TabRootView(appStore: appStore, editorOnly: editorOnly)
            }
#endif
        }
        .navigationTitle("MasterRPG")
        .setWideMode()
        .accentColor(.teal)
        .tint(.teal)
        .environment(\.gameModus, appStore.settingsModel.gameModus)
        .environment(\.mapActions, appStore.mapRoot.mapActions)
        .environment(\.networkActions, appStore.gameRoot.networkActions())
        .environment(\.routeActions, appStore.routeActions)
        .environment(\.sharingControlActions, appStore.gameRoot.sharingControlActions)
        .environment(\.sharingFeatureActions, appStore.gameRoot.sharingFeatureActions)
        .environment(\.showGameActions, appStore.settingsModel.showGameActions)
        .environment(\.valueActions, appStore.valueRoot.valueActions)
        .environment(appStore)
        .environment(appStore.adventureRoot)
        .environment(appStore.audioRoot)
        .environment(appStore.diceRoot)
        .environment(appStore.mapRoot)
        .environment(appStore.pdfRoot)
        .environment(appStore.photoRoot)
        .environment(appStore.spaceRoot)
        .environment(appStore.tableRoot)
        .environment(appStore.valueRoot)
        .environment(appStore.weatherRoot)
        .environment(appStore.optionKeyDownModel)
        .environment(appStore.settingsModel)
        .environment(appStore.selectionSheetLinkModel)
        .environment(appStore.deviceRotationModel)
        .environment(\.navigator, appStore.navigator)
        .appExitNotifications(handler: appStore.adventureRoot.save)
        .modifier(UserSettingsViewModifier(appStore: appStore))
        .observeRotate(with: appStore.deviceRotationModel)
        .task {
#if os(tvOS)
            try? await Task.sleep(for: .seconds(1))
            if appStore.photoRoot.itemControllable.itemDataModel.items.isEmpty {
                appStore.installExampleData(isGerman: locale.identifier.hasPrefix("de"))
                try? await Task.sleep(for: .seconds(1))
                appStore.adventureRoot.validate(validateFiles: true)
            }
#else
            try? await Task.sleep(for: .seconds(1))
            if appStore.settingsModel.firstLaunch {
                showFirstLunchAlert.toggle()
            }
            try? await Task.sleep(for: .seconds(5))
            try? await appStore.audioRoot.moveFiles()
            try? await appStore.pdfRoot.moveFiles()
            try? await appStore.photoRoot.moveFiles()
            try? await appStore.spaceRoot.moveFiles()
#endif
        }
        .alert("First Launch", isPresented: $showFirstLunchAlert) {
            Button {
                appStore.installExampleData(isGerman: locale.identifier.hasPrefix("de"))
                appStore.settingsModel.firstLaunch = false
                withAnimation { showFirstDataAlert.toggle() }
            } label: {
                Text("Initialize")
            }
            
            Button {
                appStore.settingsModel.firstLaunch = false
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
    RootView(appStore: .preview, editorOnly: false)
}

#Preview("Editor") {
    RootView(appStore: .preview, editorOnly: true)
}
