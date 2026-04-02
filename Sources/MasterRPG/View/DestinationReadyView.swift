// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import SwiftUI

struct DestinationReadyView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        RootView(appModel: appModel)
            .onChange(of: appModel.settingsModel.useCloudKit) {
                if appModel.databaseModel.resetDatabase(useCloudKit: appModel.settingsModel.useCloudKit) {
                    withAnimation {
                        appModel.hasDatabase = false
                    }
                }
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

