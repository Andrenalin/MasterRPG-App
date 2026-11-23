// @copyright André Trettin

import CharacterRPG
import CoreRPG
import MapRPG
import SwiftUI

struct BattleRoundView: View {
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel
    /// Shown in the game screen's side panel instead of its own window: the panel's
    /// content takes its top margin from `gameSidePanelContent`.
    var isSidePanel = false

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        @Bindable var screenModel = screenModel
        ManagedNavigationStack(name: "BattleRound") {
            VStack(spacing: 0) {
                BattleRoundHeader(
                    isRunning: controller.model.isRunning,
                    round: controller.model.roundCounter,
                    activeAttackerName: screenModel.activeAttackerName(hidingPins: controller.hiddenPinIds),
                    controller: controller,
                    isConfigurationExpanded: $screenModel.isConfigurationExpanded,
                    requestEnd: screenModel.requestEnd
                )
#if os(tvOS)
                .focusSection()
#endif

                // The scrolling list owns its scroll position, so a position
                // update re-evaluates only that view, not this header.
                BattleRoundScrollContent(
                    controller: controller,
                    screenModel: screenModel
                )
#if os(tvOS)
                .focusSection()
#endif
            }
            .navigationTitle(Text("Battle Round", bundle: .module))
            .battleHiddenNavigationBar()
            .applyIf(isSidePanel) {
                $0.gameSidePanelContent()
            }
        }
        .themedSurface()
        .confirmationDialog(
            Text("End Battle?", bundle: .module),
            isPresented: $screenModel.isEndConfirmationPresented,
            titleVisibility: .visible
        ) {
            Button(role: .destructive) {
                controller.end()
            } label: {
                Text("End Battle", bundle: .module)
            }
            Button(role: .cancel) {
            } label: {
                Text("Cancel", bundle: .module)
            }
        } message: {
            Text("The turn order and all rolls of this battle are discarded.", bundle: .module)
        }
        // The modal Character/value list. macOS never presents it: there the
        // same list is the window's inspector.
        .sheet(item: $screenModel.selectionPresentation) { _ in
            ManagedPresentationView {
                controller.root.characterRoot.viewController.linkListView(
                    type: .selection,
                    itemSelectionModel: screenModel.activeSelectionModel
                )
            }
        }
        .onChange(of: screenModel.selectedCharacter.selection) { old, new in
            screenModel.selectionDidChange(old, new, controller: controller)
        }
        .onChange(of: screenModel.selectedValue.selection) { old, new in
            screenModel.valueSelectionDidChange(old, new, controller: controller)
        }
    }
}

#Preview("Battle Round", traits: .mockData) {
    let controller = BattleRoundController.preview()
    BattleRoundView(
        controller: controller,
        screenModel: BattleRoundScreenModel(model: controller.model)
    )
    .setAppSizeMode()
    .environment(AppFocusModel())
}
