// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DatabaseInitializationView: View {
    @Environment(AppModel.self) private var appModel

    @State private var showDeleteAlert = false
    @State private var showAccountAlert = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        VStack(spacing: 20) {
            Text("Initializing Database")
                .font(.largeTitle)

            if appModel.databaseModel.hasError {
                errorView
            } else {
                // Fix #4: ProgressView with a label provides automatic
                // accessibility description — no separate Text needed.
                ProgressView("Setting up your database...")
                    .progressViewStyle(.circular)
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
        // Fix #3: alert is now on the VStack container instead of the Button.
        VStack(spacing: 16) {
            // Fix #4: explicit accessibility label for the decorative SF Symbol.
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.largeTitle)
                .foregroundStyle(.red)
                .accessibilityLabel("Database error")

            Text(appModel.databaseModel.errorMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button("Delete Database", systemImage: "trash", role: .destructive) {
                showDeleteAlert = true
            }
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

    private func initializeDatabase() async {
        // Fix #2: iCloudAccount demoted to a local variable — it was @State
        // but never read in body, so it had no effect on rendering.
        if appModel.settingsModel.useCloudKit {
            let iCloudAccount = await CloudKitAccountController.checkAccountStatus()
            if iCloudAccount != .available {
                showAccountAlert = true
                return
            }
        }
        appModel.databaseModel.setup()
    }

    private func setupRootModels() async {
        // Fix #5: removed the 250 ms Task.sleep workaround.
        // context being non-nil already guarantees the Core Data stack is ready;
        // the sleep was hiding an initialisation race that should be fixed at
        // the source (context is only set non-nil once the stack is usable).
        guard let context = appModel.databaseModel.context else { return }
        appModel.setupRootModels(
            context: context,
            batchContext: appModel.databaseModel.batchContext,
            spotlightIndexer: appModel.databaseModel.spotlightIndexer,
            coreDataInitModel: appModel.databaseModel.coreDataInitModel
        )
//        
//        do {
//            guard let context = appModel.databaseModel.context else { return }
//
//            // Small delay to ensure context is fully ready
//            try await Task.sleep(for: .milliseconds(250))
//
//            appModel.setupRootModels(
//                context: context,
//                batchContext: appModel.databaseModel.batchContext,
//                spotlightIndexer: appModel.databaseModel.spotlightIndexer,
//                coreDataInitModel: appModel.databaseModel.coreDataInitModel
//            )
//        } catch is CancellationError {
//            // Task was cancelled, context changed - this is normal
//            return
//        } catch {
//            // Log unexpected errors but don't crash
//            print("Error during root model setup: \(error)")
//        }
    }
}
