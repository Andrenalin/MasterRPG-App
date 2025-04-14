// @copyright André Trettin

import AndrenalinKit
import RoleGameKit
import SwiftUI

struct InitialRootView: View {
    let databaseModel: DataBaseModel
    let appStore: AppStore
    let editorOnly: Bool
    
    @State private var showDeleteAlert = false
    
    @State private var showAccountAlert = false
    @State private var iCloudAccount: CloudKitAccountStatus = .notChecked
    
    var body: some View {
        let _ = Self._printChanges()
        Group {
            if appStore.hasDatabase {
                RootView(appStore: appStore, editorOnly: editorOnly)
                    .onChange(of: appStore.settingsModel.useCloudKit, initial: false) {
                        if databaseModel.resetDatabase(useCloudKit: appStore.settingsModel.useCloudKit) {
                            withAnimation {
                                appStore.hasDatabase = false
                            }
                        }
                    }
            } else {
                VStack {
                    Text("Init Database").font(.largeTitle).padding()

                    if appStore.hasDatabase {
                        Text("Database is loaded")
                    } else {
                        if databaseModel.hasError {
                            Text("\(databaseModel.errorMessage)")
                                .padding()

                            Button(role: .destructive) {
                                showDeleteAlert.toggle()
                            } label: {
                                Label("Delete Database", systemImage: "trash")
                            }
                            .alert("Do you really want to delete the Database", isPresented: $showDeleteAlert) {
                                Button(role: .destructive) {
                                    databaseModel.deleteDatabase()
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        } else {
                            ProgressView().progressViewStyle(.circular)
                        }
                    }
                }
                .task {
                    if UserDefaults.standard.bool(forKey: UserSettingsViewModifier.useCloudKit) {
                        iCloudAccount = await CloudKitAccountController.checkAccountStatus()
                        if iCloudAccount != .available {
                            showAccountAlert.toggle()
                            return
                        }
                    }
                    databaseModel.setup()
                }
                .onChange(of: databaseModel.context, initial: true) {
                    guard let context = databaseModel.context else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        appStore.setupRootModels(context: context)
                    }
                }
                .alert("iCloud Account issues", isPresented: $showAccountAlert) {
                    Button(role: .cancel) {
                        databaseModel.setup()
                    } label: {
                        Label("Ok", systemImage: "checkmark")
                    }
                } message: {
                    Text("The iCloud account is not available. Please check the iCloud settings. If you continue the data cannot be sync between devices.")
                }
            }
        }
    }
}

struct DataBaseAppStoreAvailable<Content: View>: View {
    let appStore: AppStore
    let contentView: (AppStore) -> Content
    
    var body: some View {
        if appStore.hasDatabase {
            contentView(appStore)
        } else {
            Text("Wait for Database initialization...")
                .font(.largeTitle)
                .padding()
        }
    }
}

#Preview {
    InitialRootView(databaseModel: .previewWithOutSetup(), appStore: .previewWithoutDatabase, editorOnly: true)
        .frame(width: 400, height: 400)
}
