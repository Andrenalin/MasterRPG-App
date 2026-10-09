// @copyright André Trettin

import CharacterRPG
import CoreRPG
import MapRPG
import SwiftUI

struct BattleRoundView: View {
    let controller: BattleRoundController
    let screenModel: BattleRoundScreenModel

    @Environment(ScenesManager.self) private var scenesManager

    private var root: MapRootModel { controller.root.mapRoot }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        @Bindable var screenModel = screenModel
        ManagedNavigationStack(name: "BattleRound") {
            VStack(spacing: 0) {
                BattleRoundHeader(
                    isRunning: controller.model.isRunning,
                    round: controller.model.roundCounter,
                    activeAttackerName: screenModel.activeAttackerName,
                    initiativeOrder: controller.model.initiativeOrder,
                    controller: controller,
                    isConfigurationExpanded: $screenModel.isConfigurationExpanded
                )
#if os(tvOS)
                .focusSection()
#endif

                ScrollView {
                    LazyVStack {
                        if screenModel.isConfigurationExpanded {
                            BattleRoundSettingsView(
                                settings: root.mapGameControllable.battleRoundSettings,
                                controller: controller,
                                screenModel: screenModel
                            )
                            // Capped rather than left to grow: this panel sits above the battle
                            // card ScrollView in the same VStack, so an unbounded height would
                            // starve the card list below it.
                            .frame(maxHeight: 280)
                            .transition(.move(edge: .top).combined(with: .opacity))
        #if os(tvOS)
                            .focusSection()
        #endif
                        }

                        if controller.model.isRunning, !controller.model.entries.isEmpty {
                            BattleRoundList(
                                cards: controller.model.cardPresentations,
                                controller: controller,
                                screenModel: screenModel,
                                showCharacter: showCharacter,
                                selectHitPoints: selectHitPoints,
                                selectInitiative: selectInitiative
                            )
                        } else {
                            BattleRoundEmptyState(
                                isRunning: controller.model.isRunning,
                                start: { controller.start() }
                            )
                        }
                    }
                }
#if os(tvOS)
                .focusSection()
#endif
            }
            .navigationTitle(Text("Battle Round", bundle: .module))
            .battleHiddenNavigationBar()
        }
        .themedSurface()
        .sheet(item: $screenModel.presentation) { presentation in
            switch presentation {
            case .sheet(let sheet):
                BattleCharacterSheetPresentationView(presentation: sheet)
            case .selection:
                ManagedPresentationView {
                    controller.root.characterRoot.viewController.linkListView(
                        type: .selection,
                        itemSelectionModel: screenModel.pendingValueSelection == nil
                            ? screenModel.selectedCharacter
                            : screenModel.selectedValue
                    )
                }
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

private extension BattleRoundView {
    // Stable method references instead of closures recreated fresh every
    // `body` evaluation — `BattleRoundCard`'s `.equatable()` already excludes
    // these from equality since closures are never `Equatable`, but reusing
    // the same underlying method avoids needlessly reallocating three
    // closures on every live Battle Round tick.
    @MainActor
    func showCharacter(_ combatant: BattleCombatant) {
        screenModel.showCharacterSheet(combatant, controller: controller, scenesManager: scenesManager)
    }

    @MainActor
    func selectHitPoints(_ combatant: BattleCombatant) {
        screenModel.selectHitPoints(combatant, controller: controller, scenesManager: scenesManager)
    }

    @MainActor
    func selectInitiative(_ combatant: BattleCombatant) {
        screenModel.selectInitiative(combatant, controller: controller, scenesManager: scenesManager)
    }
}

#Preview("Battle Round", traits: .mockData) {
    let controller = BattleRoundController.preview()
    BattleRoundView(
        controller: controller,
        screenModel: BattleRoundScreenModel(model: controller.model, layout: .wide)
    )
    .setAppSizeMode()
    .environment(AppFocusModel())
}
