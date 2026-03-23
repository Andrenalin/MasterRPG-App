// @copyright André Trettin

import CoreRPG
import RolePlayGameKit
import SwiftUI
import SwiftData

struct InitialRootView: View {
    let appModel: AppModel
    let editorOnly: Bool

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
        DatabaseInitializationView(appModel: appModel)
    }

    private func handleCloudKitSettingChange() {
        if appModel.databaseModel.resetDatabase(useCloudKit: appModel.settingsModel.useCloudKit) {
            withAnimation {
                appModel.hasDatabase = false
            }
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

struct DatabaseInitializationView: View {
    let appModel: AppModel
    
    @State private var showDeleteAlert = false
    @State private var showAccountAlert = false

    @State private var iCloudAccount: CloudKitAccountStatus = .notChecked

    var body: some View {
        VStack(spacing: 20) {
            Text("Initializing Database")
                .font(.largeTitle)

            if appModel.databaseModel.hasError {
                errorView
            } else {
                ProgressView()
                    .progressViewStyle(.circular)
                Text("Setting up your database...")
                    .foregroundStyle(.secondary)
            }
        }
        .padding()
        .task {
            await initializeDatabase()
        }
        .alert("iCloud Account Issues", isPresented: $showAccountAlert) {
            Button("Continue Anyway") {
                appModel.databaseModel.setup()
            }
        } message: {
            Text("The iCloud account is not available. Please check your iCloud settings. If you continue, data cannot be synced between devices.")
        }
        .task(id: appModel.databaseModel.context) {
            await setupRootModels()
        }
    }

    @ViewBuilder
    private var errorView: some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)

            Text(appModel.databaseModel.errorMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Delete Database", systemImage: "trash", role: .destructive) {
                showDeleteAlert = true
            }
            .alert("Delete Database?", isPresented: $showDeleteAlert) {
                Button("Cancel", role: .cancel) { }
                Button("Delete", role: .destructive) {
                    appModel.databaseModel.deleteDatabase()
                }
            } message: {
                Text("This will permanently delete the database. This action cannot be undone.")
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
        appModel.databaseModel.setup()
    }
    
    private func setupRootModels() async {
        // Setup root models when database context becomes available
        guard let context = appModel.databaseModel.context else { return }

        do {
            // Small delay to ensure context is fully ready
            try await Task.sleep(for: .milliseconds(250))

            appModel.setupRootModels(
                context: context,
                batchContext: appModel.databaseModel.batchContext,
                spotlightIndexer: appModel.databaseModel.spotlightIndexer,
                coreDataInitModel: appModel.databaseModel.coreDataInitModel
            )
        } catch is CancellationError {
            // Task was cancelled, context changed - this is normal
            return
        } catch {
            // Log unexpected errors but don't crash
            print("Error during root model setup: \(error)")
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
