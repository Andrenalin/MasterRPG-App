// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DestinationReadyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.locale) private var locale: Locale
    @Environment(\.navigator) private var navigator

    @State private var showFirstLunchAlert = false
    @State private var showFirstDataAlert = false
    @State private var showValidateAlert = false

    var body: some View {
        let _ = Self._printChanges()
        appModel.appNavigationModel.modeRouteType
            .onChange(of: appModel.settingsModel.useCloudKit) {
                if appModel.databaseModel.resetDatabase(useCloudKit: appModel.settingsModel.useCloudKit) {
                    withAnimation {
                        appModel.appNavigationModel.initialRouteType = .initializing
                    }
                }
            }
            .task {
                if appModel.settingsModel.firstLaunch {
                    showFirstLunchAlert = true
                }
                guard !appModel.settingsModel.firstLaunch && appModel.settingsModel.needsValidateDatabase else { return }
                showValidateAlert = true
            }
            .alert("Validate Database", isPresented: $showValidateAlert) {
                Button {
                    appModel.settingsModel.needsValidateDatabase = false
                    navigator.navigate(to: SettingsRoute.validate, method: .managedSheet)
                } label: {
                    Text("Validate")
                }
                Button(role: .cancel) {
                    appModel.settingsModel.needsValidateDatabase = false
                } label: {
                    Text("Not Now")
                }
            } message: {
                Text("It is recommended to validate the database to ensure your data is consistent.")
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

public struct DataBaseAppStoreAvailable<Content: View>: View {
    public init(appModel: AppModel, contentView: @escaping (AppModel) -> Content) {
        self.appModel = appModel
        self.contentView = contentView
    }
    
    let appModel: AppModel
    let contentView: (AppModel) -> Content

    public var body: some View {
        let _ = Self._printChanges()
        if appModel.appNavigationModel.initialRouteType == .ready {
            contentView(appModel)
        } else {
            Text("Wait for Database initialization...")
                .font(.largeTitle)
                .padding()
        }
    }
}

