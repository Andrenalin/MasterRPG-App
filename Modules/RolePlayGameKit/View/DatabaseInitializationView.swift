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
            Text("Initializing Database", bundle: .module)
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
            Button { appModel.databaseModel.setup() } label: { Text("Continue Anyway", bundle: .module) }
        } message: {
            Text("The iCloud account is not available. Please check your iCloud settings. If you continue, data cannot be synced between devices.", bundle: .module)
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
                .accessibilityLabel(Text("Database error", bundle: .module))

            Text(appModel.databaseModel.errorMessage)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)

            Button(role: .destructive) { showDeleteAlert = true } label: {
                Label { Text("Delete Database", bundle: .module) } icon: { Image(systemName: "trash") }
            }
        }
        .alert("Delete Database?", isPresented: $showDeleteAlert) {
            Button(role: .cancel) { } label: { Text("Cancel", bundle: .module) }
            Button(role: .destructive) { appModel.databaseModel.deleteDatabase() } label: { Text("Delete", bundle: .module) }
        } message: {
            Text("This will permanently delete the database. This action cannot be undone.", bundle: .module)
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
        guard let context = appModel.databaseModel.context else { return }
        appModel.setupRootModels(
            context: context,
            batchContext: appModel.databaseModel.batchContext,
            spotlightIndexer: appModel.databaseModel.spotlightIndexer,
            coreDataInitModel: appModel.databaseModel.coreDataInitModel
        )
    }
}

#Preview {
    DatabaseInitializationView()
}
