// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DatabaseInitializationView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.rolePlayDatabaseInitializationEnabled) private var databaseInitializationEnabled

    @State private var showDeleteAlert = false
    @State private var showAccountAlert = false

    private let performsInitialization: Bool

    init(performsInitialization: Bool = true) {
        self.performsInitialization = performsInitialization
    }

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
                ProgressView {
                    Text("Setting up your database...", bundle: .module)
                }
                    .progressViewStyle(.circular)
            }
        }
        .padding()
        .task {
            guard performsInitialization && databaseInitializationEnabled else { return }
            await initializeDatabase()
        }
        .alert(Text("iCloud Account Issues", bundle: .module), isPresented: $showAccountAlert) {
            Button { appModel.databaseModel.setup() } label: { Text("Continue Anyway", bundle: .module) }
        } message: {
            Text("The iCloud account is not available. Please check your iCloud settings. If you continue, data cannot be synced between devices.", bundle: .module)
        }
        .task(id: appModel.databaseModel.context) {
            guard performsInitialization && databaseInitializationEnabled else { return }
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
                .accessibilityHidden(true)

            Text("Database error", bundle: .module)
                .font(.headline)

            if let errorMessage = appModel.databaseModel.errorMessage {
                Text(verbatim: errorMessage)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            Button(role: .destructive) { showDeleteAlert = true } label: {
                Label { Text("Delete Database", bundle: .module) } icon: { Image(systemName: "trash") }
            }
        }
        .alert(Text("Delete Database?", bundle: .module), isPresented: $showDeleteAlert) {
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
    DatabaseInitializationView(performsInitialization: false)
        .environment(AppModel.previewWithoutDatabase)
}

extension EnvironmentValues {
    @Entry var rolePlayDatabaseInitializationEnabled: Bool = true
}

extension View {
    func rolePlayDatabaseInitializationEnabled(_ isEnabled: Bool) -> some View {
        environment(\.rolePlayDatabaseInitializationEnabled, isEnabled)
    }
}
