// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

/// Toggles the platform's 3D table presentation. visionOS keeps its independent
/// TabletopKit volume; iOS and macOS replace the 2D map canvas in place.
@MainActor
struct GameTableWindowButton: View {
    let root: GameRoot
    let isMaster: Bool

#if os(visionOS)
    @Environment(ScenesManager.self) private var scenesManager
    @Environment(GameScreenModel.self) private var gameScreenModel
    @Environment(\.pushWindow) private var pushWindow
    @Environment(\.accessibilityReduceMotion) private var accessibilityReduceMotion

    /// True from the tap that opens the table until the table window is requested, so a second
    /// tap in between cannot push the game window twice.
    @State private var isOpeningTable = false
#endif
    @Environment(AppSettingsModel.self) private var appSettingsModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        Button(action: toggleTable) {
            Label {
                Text(actionTitle)
            } icon: {
                Image(systemName: "cube.transparent")
            }
        }
        .selectedRoundButton(
            title: String(localized: actionTitle),
            module: .map,
            isSelected: isPresented
        )
    }

    private var isPresented: Bool {
#if os(visionOS)
        switch scenesManager.getSceneState(for: SceneId.gameTable) {
        case .opening, .opened:
            true
        case .closing, .closed:
            false
        }
#else
        appSettingsModel.showGameTableVolume
#endif
    }

    private var actionTitle: LocalizedStringResource {
#if os(visionOS)
        isPresented
            ? LocalizedStringResource("Hide Table Volume", bundle: .module)
            : LocalizedStringResource("Show Table Volume", bundle: .module)
#else
        isPresented
            ? LocalizedStringResource("Show 2D Map", bundle: .module)
            : LocalizedStringResource("Show 3D Table", bundle: .module)
#endif
    }

    private func toggleTable() {
#if os(visionOS)
        guard !isOpeningTable else { return }
#endif
        let shouldShow = !isPresented
        appSettingsModel.showGameTableVolume = shouldShow
#if os(visionOS)
        if shouldShow {
            
            // Keep the table and the main "Game" window (`SceneId.game` —
            // the app's primary navigation window, distinct from both the
            // table and the floating adventure/character window below)
            // mutually exclusive on visionOS: unlike iOS/macOS (which swap
            // the map/table in place within one window), these are separate
            // windows there, so leaving the game window open behind the
            // table would just be redundant clutter.
            pushWindow(id: SceneId.gameRecover.rawValue)
            // The table opens only once the recover window stands where the game window was:
            // the system opens a new window in front of the app's existing windows, so the table
            // now lands in front of the recover window instead of in front of a game window that
            // is about to be pushed away.
            isOpeningTable = true
            Task {
                await openTableOnceRecoverWindowStands()
                isOpeningTable = false
            }
            // Also close the floating adventure/character window
            // (`GameWindowMenuButtonView`'s own window) the same way opening
            // the table already implies closing the game window it lives in.
            GameWindowToggle.close(
                isMaster: isMaster,
                scenesManager: scenesManager,
                gameScreenModel: gameScreenModel,
                appSettingsModel: appSettingsModel
            )
        } else {
            scenesManager.dismissWindow(SceneId.gameTable)
            // Mirrors the open half of the exclusivity above: closing the
            // table (whether from the game window's own toolbar or the
            // table's own ornament) brings the main game window back.
            scenesManager.dismissWindow(SceneId.gameRecover)
            // ...and the floating adventure/character window, the same way
            // `GameWindowMenuButtonView` would open it directly.
            GameWindowToggle.open(
                isMaster: isMaster,
                itemId: isMaster ? root.gameModel.gameConfig.master.adventureId : root.gameModel.selectedCharacter,
                scenesManager: scenesManager,
                gameScreenModel: gameScreenModel,
                appSettingsModel: appSettingsModel,
                animated: !accessibilityReduceMotion
            )
        }
#endif
    }
}

#if os(visionOS)
private extension GameTableWindowButton {
    /// Waits (at most about a second) until the pushed-in recover window is on screen, then opens
    /// the table. Opens it anyway on a timeout, so the table can never be left unreachable.
    func openTableOnceRecoverWindowStands() async {
        for _ in 0..<20 {
            if scenesManager.getSceneState(for: SceneId.gameRecover) == .opened { break }
            guard (try? await Task.sleep(for: .milliseconds(50))) != nil else { break }
        }
        scenesManager.openWindow(SceneId.gameTable)
    }
}
#endif

#Preview(traits: .mockData) {
    GameTableWindowButton(root: .preview, isMaster: true)
        .environment(GameScreenModel())
}
#endif
