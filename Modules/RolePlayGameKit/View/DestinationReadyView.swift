// @copyright André Trettin

import CoreRPG
import SwiftUI

struct DestinationReadyView: View {
    @Environment(AppModel.self) private var appModel
    @Environment(\.locale) private var locale: Locale
    @Environment(\.navigator) private var navigator

    // Fix #4: single Identifiable enum replaces three separate Bool @State
    // properties. Only one alert can be active at a time; using an enum makes
    // that constraint explicit and prevents the three-alert priority ambiguity.
    private enum ActiveAlert: Identifiable {
        case firstLaunch, dataInstalled, validateDatabase
        var id: Self { self }
    }

    @State private var activeAlert: ActiveAlert?

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()

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
                    activeAlert = .firstLaunch
                    return
                }
                if appModel.settingsModel.needsValidateDatabase {
                    activeAlert = .validateDatabase
                }
            }
            // Fix #4 (continued): single alert modifier driven by the enum.
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
                        appModel.installExampleData(isGerman: locale.identifier.hasPrefix("de"))
                        appModel.settingsModel.firstLaunch = false
                        // Yield so dismiss completes before we present the
                        // follow-up alert.
                        Task { @MainActor in activeAlert = .dataInstalled }
                    } label: {
                        Text("Initialize")
                    }
                    Button {
                        appModel.settingsModel.firstLaunch = false
                    } label: {
                        Text("Not now")
                    }

                case .dataInstalled:
                    Button("OK") { }

                case .validateDatabase:
                    Button {
                        appModel.settingsModel.needsValidateDatabase = false
                        navigator.navigate(to: SettingsRoute.validate, method: .managedSheet)
                    } label: {
                        Text("Validate")
                    }
                    Button(role: .cancel) { } label: {
                        Text("Not Now")
                    }
                }
            } message: { kind in
                // Fix #1: corrected "first lunch" → "first launch",
                // "Explaination" → "Example", and other typos throughout.
                switch kind {
                case .firstLaunch:
                    Text("This is the first launch and there is no data in the database. Do you want to initialize the database with example data? No download is required — the example data is pre-bundled.")
                case .dataInstalled:
                    Text("The example data has been installed. You will find the data in the other sections.")
                case .validateDatabase:
                    Text("It is recommended to validate the database to ensure your data is consistent.")
                }
            }
    }

    // Computed Text property keeps the alert call site clean and avoids
    // LocalizedStringKey/String type-inference ambiguity at the call site.
    private var alertTitle: Text {
        switch activeAlert {
        case .firstLaunch:      Text("First Launch")
        case .dataInstalled:    Text("Example Data")
        case .validateDatabase: Text("Validate Database")
        case nil:               Text("")
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

    // Set to true once we confirm the Game window is not open and this
    // Editor window must own database initialisation itself.
    // Required on macOS: window restoration can bring back only the Editor
    // window, leaving DatabaseInitializationView (which lives in the Game
    // window's route) never shown — so initialRouteType would stay
    // .initializing forever.
    @State private var shouldInitDatabase = false

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        // Fix #6: extract the single property we actually read so @Observable
        // tracking stays narrow — the view won't re-render for unrelated
        // AppModel changes.
        let isReady = appModel.appNavigationModel.initialRouteType == .ready
        // Fix #7: animate the switch so the waiting text fades out instead of
        // cutting to content abruptly on first launch.
        Group {
            if isReady {
                contentView(appModel)
            } else if shouldInitDatabase {
                // Editor window is taking responsibility for database init
                // because Game window is not open.
                DatabaseInitializationView()
            } else {
                Text("Waiting for database initialization…")
                    .font(.largeTitle)
                    .padding()
            }
        }
        .animation(.easeInOut, value: isReady)
        .task {
            await checkIfEditorShouldHandleDatabaseInit()
        }
    }

    // Checks once — asynchronously after the first layout pass — whether the
    // Game window has registered itself with the ScenesManager. If it has not,
    // the Editor window takes over database initialisation.
    //
    // Why the sleep? SceneTrackerModifier's `onChange(of: scenePhase,
    // initial: true)` fires synchronously during the first update pass, before
    // any `.task` closure runs. The 150 ms sleep is purely a safety margin for
    // edge cases where macOS restores both windows at the same instant and the
    // Game window's tracker hasn't fired yet. It is imperceptible to the user.
    private func checkIfEditorShouldHandleDatabaseInit() async {
        guard appModel.appNavigationModel.initialRouteType != .ready else { return }
        try? await Task.sleep(for: .milliseconds(150))
        // Re-check: Game window might have finished init during the sleep.
        guard appModel.appNavigationModel.initialRouteType != .ready else { return }
        // appModel.scenesManager is @ObservationIgnored + let — accessing it
        // here (inside the task, outside the tracking window) registers zero
        // tracking dependencies on DataBaseAppStoreAvailable.
        let gameState = appModel.scenesManager.getSceneState(for: .game)
        if gameState != .opened && gameState != .opening {
            shouldInitDatabase = true
        }
    }
}
