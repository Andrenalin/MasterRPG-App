// @copyright André Trettin

#if os(visionOS)
import CoreRPG
import SwiftUI

/// What the start window shows on visionOS once the game runs: the game lives at the 3D table, so
/// this opens the table and closes the window (`GameTablePresentationController`). The button is
/// the way on when the table did not open, so the window never leaves the game unreachable.
///
/// visionOS has no hook to stop the system's close button of the table window
/// (`dismissalConfirmationDialog` is unavailable there), so closing the table brings this window
/// back instead, with the question whether to quit the game. The game keeps running meanwhile.
struct GameTableLaunchView: View {
    // Scaled with Dynamic Type instead of fixed points. See CODE_AUDIT_29 §8.7.
    @ScaledMetric private var spacing24: CGFloat = 24
    let root: GameRoot

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(AppGameStateModel.self) private var appGameStateModel: AppGameStateModel?

    private var controller: GameTablePresentationController {
        GameTablePresentationController(root: root, scenesManager: scenesManager, appGameStateModel: appGameStateModel)
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        VStack(spacing: spacing24) {
            ProgressView()
            Text("Game is running", bundle: .module)
                .font(.title2)
            Button {
                let controller = controller
                Task { await controller.showTable() }
            } label: {
                Label {
                    Text("Show 3D Table", bundle: .module)
                } icon: {
                    Image(systemName: "cube.transparent")
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .themedSurface()
        .task {
            await controller.openAtGameStart()
        }
        .alert(
            Text("Quit Game?", bundle: .module),
            isPresented: Bindable(root.gameModel.tablePresentation).asksToQuit
        ) {
            Button(role: .destructive) {
                let controller = controller
                Task { await controller.endGame() }
            } label: {
                Text("Quit", bundle: .module)
            }
            Button {
                let controller = controller
                Task { await controller.showTable() }
            } label: {
                Text("Show 3D Table", bundle: .module)
            }
        } message: {
            Text("Do you really want to quit the game?", bundle: .module)
        }
        .onDisappear {
            let controller = controller
            Task { await controller.launchWindowDidDisappear() }
        }
    }
}
#endif
