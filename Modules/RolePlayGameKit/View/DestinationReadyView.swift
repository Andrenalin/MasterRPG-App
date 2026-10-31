// @copyright André Trettin

import CoreRPG
import CharacterRPG
import SwiftUI

struct DestinationReadyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.locale) private var locale: Locale
    @Environment(\.navigator) private var navigator
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    // A single Identifiable enum drives the alerts instead of three separate Bool @State
    // properties. Only one alert can be active at a time; using an enum makes
    // that constraint explicit and prevents the three-alert priority ambiguity.
    private enum ActiveAlert: Identifiable, Hashable {
        case firstLaunch, dataInstalled, validateDatabase
        case dataInstallFailed(String)
        var id: Self { self }
    }

    /// Delay before running the deferred database cleanup pass on first launch — gives the
    /// view's own initial layout/alert-presentation work priority. See CODE_AUDIT §9.14.
    private static let databaseCleanupDelay: Duration = .seconds(5)

    @State private var activeAlert: ActiveAlert?

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

        appModel.appNavigationModel.modeRouteType
            .onChange(of: appModel.settingsModel.useCloudKit) {
                if appModel.databaseModel.resetDatabase(useCloudKit: appModel.settingsModel.useCloudKit) {
                    withAnimation(reduceMotion ? nil : .default) {
                        appModel.appNavigationModel.initialRouteType = .initializing
                    }
                }
            }
            .task {
                appModel.refreshTipEligibility()
                if appModel.settingsModel.firstLaunch {
                    activeAlert = .firstLaunch
                    appModel.settingsModel.needsValidateDatabase = false
                    return
                }
                if appModel.settingsModel.needsValidateDatabase {
                    activeAlert = .validateDatabase
                }
                try? await Task.sleep(for: Self.databaseCleanupDelay)
                guard !Task.isCancelled else { return }
                await appModel.cleanDatabase()
            }
            // A single alert modifier driven by the enum.
            // The `presenting:` overload passes the current case into both the
            // actions and message builders, so each case can provide its own
            // buttons and copy without separate alert modifiers.
            //
            // Chaining firstLaunch → dataInstalled:
            // When the user taps "Initialize", we schedule the next alert via
            // Task { @MainActor in } so it runs after the current alert's
            // dismiss cycle (isPresented set closure) completes. Without the
            // Task yield the dismiss binding would overwrite the assignment.
            .alert(
                alertTitle,
                isPresented: Binding(
                    get: { activeAlert != nil },
                    set: { if !$0 { activeAlert = nil } }
                ),
                presenting: activeAlert
            ) { kind in
                switch kind {
                case .firstLaunch:
                    Button {
                        appModel.settingsModel.firstLaunch = false
                        let isGerman = locale.identifier.hasPrefix("de")
                        // The follow-up alert reports the real result once the import has
                        // finished (which also lets this alert's dismissal complete first),
                        // not "installed" before it ran. See CODE_AUDIT_Folder §3.7.
                        Task { @MainActor in
                            do {
                                try await appModel.installExampleData(isGerman: isGerman)
                                activeAlert = .dataInstalled
                            } catch {
                                activeAlert = .dataInstallFailed(error.localizedDescription)
                            }
                        }
                    } label: {
                        Text("Initialize", bundle: .module)
                    }
                    Button {
                        appModel.settingsModel.firstLaunch = false
                        appModel.refreshTipEligibility()
                    } label: {
                        Text("Not now", bundle: .module)
                    }

                case .dataInstalled, .dataInstallFailed:
                    Button(role: .cancel) { } label: { Text("OK", bundle: .module) }

                case .validateDatabase:
                    Button {
                        appModel.settingsModel.needsValidateDatabase = false
                        navigator.navigate(to: SettingsRoute.validate, method: .managedSheet)
                    } label: {
                        Text("Validate", bundle: .module)
                    }
                    Button(role: .cancel) { } label: {
                        Text("Not Now", bundle: .module)
                    }
                }
            } message: { kind in
                switch kind {
                case .firstLaunch:
                    Text("This is the first launch and there is no data in the database. Do you want to initialize the database with example data? No download is required — the example data is pre-bundled.", bundle: .module)
                case .dataInstalled:
                    Text("The example data has been installed. You will find the data in the other sections.", bundle: .module)
                case .dataInstallFailed(let reason):
                    Text("The example data could not be installed: \(reason)", bundle: .module)
                case .validateDatabase:
                    Text("It is recommended to validate the database to ensure your data is consistent.", bundle: .module)
                }
            }
            .environment(
                \.itemGenerationResultAction,
                ItemGenerationResultAction(id: .object(ObjectIdentifier(appModel))) { summary in
                    appModel.generatedValueEntry = ValueEntryModel(
                        generationSummary: summary
                    )
                }
            )
    }

    // Computed Text property keeps the alert call site clean and avoids
    // LocalizedStringKey/String type-inference ambiguity at the call site.
    private var alertTitle: Text {
        switch activeAlert {
        case .firstLaunch:      Text("First Launch", bundle: .module)
        case .dataInstalled:    Text("Example Data", bundle: .module)
        case .dataInstallFailed: Text("Example Data Not Installed", bundle: .module)
        case .validateDatabase: Text("Validate Database", bundle: .module)
        case nil:               Text(verbatim: "")
        }
    }
}

#Preview {
    DestinationReadyView()
        .environment(AppModel())
}
