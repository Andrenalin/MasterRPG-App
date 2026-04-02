// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import SwiftUI

struct DestinationReadyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.locale) private var locale: Locale

    @State private var showFirstLunchAlert = false
    @State private var showFirstDataAlert = false

    var body: some View {
        RootView(appModel: appModel)
            .onChange(of: appModel.settingsModel.useCloudKit) {
                if appModel.databaseModel.resetDatabase(useCloudKit: appModel.settingsModel.useCloudKit) {
                    withAnimation {
                        appModel.hasDatabase = false
                    }
                }
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

// MARK: - Database App Store Available

struct DataBaseAppStoreAvailable<Content: View>: View {
    let appModel: AppModel
    let contentView: (AppModel) -> Content

    var body: some View {
        if appModel.hasDatabase {
            contentView(appModel)
        } else {
            Text("Wait for Database initialization...")
                .font(.largeTitle)
                .padding()
        }
    }
}

