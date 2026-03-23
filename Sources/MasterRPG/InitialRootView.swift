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
                rootContentView
            } else {
                databaseInitializationView
            }
        }
        .onContinueUserActivity(UserActivity.bundleIdentifierType) { userActivity in
            handle(userActivity: userActivity)
        }
    }

    @ViewBuilder
    private var rootContentView: some View {
        RootView(appModel: appModel, editorOnly: editorOnly)
            .onChange(of: appModel.settingsModel.useCloudKit) {
                handleCloudKitSettingChange()
            }
    }

    @ViewBuilder
    private var databaseInitializationView: some View {
        DatabaseInitializationView(
            databaseModel: databaseModel,
            showDeleteAlert: $showDeleteAlert,
            showAccountAlert: $showAccountAlert
        )
        .task {
            await initializeDatabase()
        }
        .task(id: databaseModel.context) {
            await setupRootModels()
        }
        .alert("iCloud Account Issues", isPresented: $showAccountAlert) {
            Button("Continue Anyway") {
                databaseModel.setup()
            }
        } message: {
            Text("The iCloud account is not available. Please check your iCloud settings. If you continue, data cannot be synced between devices.")
        }
    }

    private func handleCloudKitSettingChange() {
        if databaseModel.resetDatabase(useCloudKit: appModel.settingsModel.useCloudKit) {
            withAnimation {
                appModel.hasDatabase = false
            }
        }
    }

    private func initializeDatabase() async {
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

    private func setupRootModels() async {
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
    
    private func handle(userActivity: NSUserActivity) {
        // SIRI & Search
        let module = UserActivity.module(from: userActivity)
        guard module != .none, let itemId = UserActivity.itemId(from: userActivity) else { return }
        let childId = UserActivity.childId(from: userActivity)
        appModel.navigator.perform(route: KnownRoutes.route(module: module, itemId: itemId, entryId: childId))
    }
}

// MARK: - Database Initialization View

private struct DatabaseInitializationView: View {
    let databaseModel: DataBaseModel
    @Binding var showDeleteAlert: Bool
    @Binding var showAccountAlert: Bool

    var body: some View {
        VStack(spacing: 20) {
            Text("Initializing Database")
                .font(.largeTitle)

            if databaseModel.hasError {
                errorView
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Setting up your database...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
    }

    @ViewBuilder
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text(databaseModel.errorMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Delete Database", systemImage: "trash", role: .destructive) {
                showDeleteAlert = true
            }
            .alert("Delete Database?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    databaseModel.deleteDatabase()
                }
            } message: {
                Text("This will permanently delete the database. This action cannot be undone.")
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

#Preview {
    InitialRootView(appModel: .previewWithoutDatabase, editorOnly: true)
        .frame(width: 400, height: 400)
}
