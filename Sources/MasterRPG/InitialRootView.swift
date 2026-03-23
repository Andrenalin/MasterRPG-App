// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import SwiftUI
import SwiftData


struct InitialRootView: View {
    let appModel: AppModel
    let editorOnly: Bool

    #if os(tvOS)
    @State private var databaseModel = DataBaseModel(useCloudKit: false, currentActor: .mainApp)
    #else
    @State private var databaseModel = DataBaseModel(useCloudKit: AppModel.shared.settingsModel.useCloudKit, currentActor: .mainApp)
    #endif
    
    @State private var showDeleteAlert = false
    @State private var showAccountAlert = false
    @State private var iCloudAccount: CloudKitAccountStatus = .notChecked

    var body: some View {
        Group {
            if appModel.hasDatabase {
                RootView(appModel: appModel, editorOnly: editorOnly)
                    .onChange(of: appModel.settingsModel.useCloudKit, initial: false) {
                        if databaseModel.resetDatabase(useCloudKit: appModel.settingsModel.useCloudKit) {
                            withAnimation {
                                appModel.hasDatabase = false
                            }
                        }
                    }
            } else {
                VStack {
                    Text("Init Database").font(.largeTitle).padding()

                    if appModel.hasDatabase {
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
                    // Check iCloud availability if CloudKit is enabled
                    if appModel.settingsModel.useCloudKit {
                        iCloudAccount = await CloudKitAccountController.checkAccountStatus()
                        if iCloudAccount != .available {
                            showAccountAlert = true
                            return
                        }
                    }
                    // Initialize database
                    databaseModel.setup()
                }
                .task(id: databaseModel.context) {
                    // Setup root models when database context becomes available
                    guard let context = databaseModel.context else { return }

                    do {
                        // Small delay to ensure context is fully ready
                        try await Task.sleep(for: .milliseconds(250))

                        appModel.setupRootModels(
                            context: context,
                            batchContext: databaseModel.batchContext,
                            spotlightIndexer: databaseModel.spotlightIndexer,
                            coreDataInitModel: databaseModel.coreDataInitModel
                        )
                    } catch is CancellationError {
                        // Task was cancelled, context changed - this is normal
                        return
                    } catch {
                        // Log unexpected errors but don't crash
                        print("Error during root model setup: \(error)")
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
        .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
            handle(userActivity: userActivity)
        }
    }
    
    func handle(userActivity: NSUserActivity) {
        // SIRI & Search
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return }
        let childId = UserActivity.childId(from: userActivity)
        appModel.navigator.perform(route: KnownRoutes.route(module: module, itemId: itemId, entryId: childId))
    }
}

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

#Preview {
    InitialRootView(appModel: .previewWithoutDatabase, editorOnly: true)
        .frame(width: 400, height: 400)
}
