// @copyright André Trettin

import MapRPG
import CoreRPG
import SwiftUI

struct BattleRoundWindowView: View {
    init(root: GameRoot) {
        self.root = root
        _screenModel = State(
            wrappedValue: BattleRoundScreenModel(model: root.battleRoundController.model)
        )
    }

    let root: GameRoot

    @Environment(ScenesManager.self) private var scenesManager
    @State private var screenModel: BattleRoundScreenModel

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        @Bindable var screenModel = screenModel
        if root.gameModel.gameConfig.isMaster {
            BattleRoundView(controller: root.battleRoundController, screenModel: screenModel)
                .environment(root.mapRoot)
                .onChange(of: root.battleRoundController.model.isRunning) { wasRunning, isRunning in
                    guard wasRunning, !isRunning else { return }
                    scenesManager.dismissWindow(.battleRound)
                }
#if os(macOS)
                .inspector(isPresented: $screenModel.isInspectorPresented) {
                    BattleRoundCharacterInspectorView(controller: root.battleRoundController, screenModel: screenModel)
                        .inspectorColumnWidth(min: 260, ideal: 320, max: 420)
                }
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            withAnimation {
                                screenModel.isInspectorPresented.toggle()
                            }
                        } label: {
                            Label {
                                Text("Inspector", bundle: .module)
                            } icon: {
                                Image(systemName: "scope")
                            }
                        }
                    }
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

#Preview(traits: .mockData) {
    BattleRoundWindowView(root: .previewFixture())
}
