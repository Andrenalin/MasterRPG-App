// @copyright André Trettin

import MapRPG
import CoreRPG
import SwiftUI

struct BattleRoundWindowView: View {
    init(root: GameRoot) {
        self.root = root
        // Lazy: a plain `State(wrappedValue:)` here built a new screen model
        // (and its two selection models) on every evaluation of the parent,
        // only for SwiftUI to throw all but the first away.
        _screenModel = CoreRPG.LazyState(
            wrappedValue: BattleRoundScreenModel(model: root.battleRoundController.model)
        )
    }

    let root: GameRoot

    @Environment(ScenesManager.self) private var scenesManager
    @CoreRPG.LazyState private var screenModel: BattleRoundScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        if root.gameModel.gameConfig.isMaster {
            let screenModel = screenModel
            BattleRoundView(controller: root.battleRoundController, screenModel: screenModel)
                .environment(root.mapRoot)
#if os(macOS)
                // The list's own least width. The window's follows from it
                // and from the inspector's, so the cards keep this width
                // while the inspector is open too.
                .frame(minWidth: BattleRoundWindowMetrics.minimumListWidth)
#endif
                .onChange(of: root.battleRoundController.model.isRunning) { wasRunning, isRunning in
                    guard screenModel.battleRunningDidChange(
                        wasRunning: wasRunning,
                        isRunning: isRunning
                    ) else { return }
                    // One main-actor turn later: the battle usually ends from
                    // a click inside this window, and this handler runs while
                    // SwiftUI is still applying that update (the card list
                    // gives way to the empty state). Closing the window from
                    // inside its own update tears it down mid-transaction.
                    let scenesManager = scenesManager
                    Task { @MainActor in
                        scenesManager.dismissWindow(.battleRound)
                    }
                }
#if os(macOS)
                .inspector(isPresented: Bindable(screenModel).isInspectorPresented) {
                    BattleRoundCharacterInspectorView(controller: root.battleRoundController, screenModel: screenModel)
                        .inspectorColumnWidth(
                            min: BattleRoundWindowMetrics.minimumInspectorWidth,
                            ideal: 320,
                            max: 420
                        )
                }
                .toolbar {
                    BattleRoundWindowToolbar(
                        controller: root.battleRoundController,
                        screenModel: screenModel
                    )
                }
#endif
        } else {
            ContentUnavailableView {
                Label {
                    Text("Game Master Only", bundle: .module)
                } icon: {
                    Image(systemName: "lock.fill")
                }
            } description: {
                Text("Only the game master can manage battle rounds.", bundle: .module)
            }
        }
    }
}

#if os(macOS)
enum BattleRoundWindowMetrics {
    /// A battle card lays out down to the width of the game's side panel.
    static let minimumListWidth: CGFloat = 400
    static let minimumInspectorWidth: CGFloat = 260
}
#endif

#Preview(traits: .mockData) {
    BattleRoundWindowView(root: .previewFixture())
}
