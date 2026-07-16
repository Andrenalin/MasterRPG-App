// @copyright André Trettin

import CoreRPG
import SwiftUI

public struct DataBaseAppStoreAvailable<Content: View>: View {
    public init(appModel: AppModel, contentView: @escaping (AppModel) -> Content) {
        self.appModel = appModel
        self.contentView = contentView
    }

    let appModel: AppModel
    let contentView: (AppModel) -> Content

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

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
                Text("Waiting for database initialization…", bundle: .module)
                    .font(.largeTitle)
                    .padding()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut, value: isReady)
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

#Preview("Database ready content") {
    DataBaseAppStoreAvailable<Text>(appModel: {
        let appModel = AppModel()
        appModel.appNavigationModel.initialRouteType = .ready
        return appModel
    }()) { _ in
        Text(verbatim: "Editor Ready")
    }
}
