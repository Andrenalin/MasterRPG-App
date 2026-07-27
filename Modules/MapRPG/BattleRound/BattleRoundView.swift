// @copyright André Trettin

import CharacterRPG
import CoreRPG
import SwiftUI

public struct BattleRoundView: View {
    public init(model: BattleRoundModel, actions: BattleRoundActions) {
        self.model = model
        self.actions = actions
        _screenModel = State(wrappedValue: BattleRoundScreenModel(model: model))
    }

    let model: BattleRoundModel
    let actions: BattleRoundActions

    @Environment(MapRootModel.self) private var root
    @Environment(ScenesManager.self) private var scenesManager
    @State private var screenModel: BattleRoundScreenModel

    public var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
        @Bindable var screenModel = screenModel
        ManagedNavigationStack(name: "BattleRound") {
            VStack(spacing: 0) {
                BattleRoundHeader(
                    isRunning: model.isRunning,
                    hasEntries: !model.entries.isEmpty,
                    round: model.roundCounter,
                    activeAttackerName: screenModel.activeAttackerName,
                    initiativeOrder: model.initiativeOrder,
                    actions: actions,
                    isConfigurationExpanded: $screenModel.isConfigurationExpanded
                )

                if screenModel.isConfigurationExpanded {
                    BattleRoundSettingsView(
                        settings: root.mapGameControllable.battleRoundSettings,
                        actions: actions,
                        selectEntry: { kind in
                            screenModel.selectConfiguredValue(
                                kind,
                                root: root,
                                scenesManager: scenesManager
                            )
                        },
                        useDroppedEntry: { value, kind in
                            screenModel.useDroppedConfiguredValue(
                                value,
                                kind: kind,
                                root: root
                            )
                        },
                        refresh: {
                            screenModel.refreshConfiguredValues(root: root)
                        }
                    )
                }

                ScrollView {
                    LazyVStack {
                        if model.isRunning, !model.entries.isEmpty {
                            BattleRoundList(
                                cards: model.cardPresentations,
                                actions: actions,
                                showCharacter: { combatant in
                                    screenModel.showCharacterSheet(
                                        combatant,
                                        root: root,
                                        scenesManager: scenesManager
                                    )
                                },
                                selectHitPoints: { combatant in
                                    screenModel.selectHitPoints(
                                        combatant,
                                        root: root,
                                        scenesManager: scenesManager
                                    )
                                }
                            )
                        } else {
                            BattleRoundEmptyState(
                                isRunning: model.isRunning,
                                start: actions.start
                            )
                        }
                    }
                }
            }
            .navigationTitle(Text("Battle Round", bundle: .module))
            .battleInlineNavigationTitle()
        }
        .sheet(item: $screenModel.presentation) { presentation in
            switch presentation {
            case .sheet(let sheet):
                BattleCharacterSheetPresentationView(presentation: sheet)
            case .selection:
                ManagedPresentationView {
                    root.viewController.characterSelection(
                        root: root,
                        selectionModel: screenModel.pendingValueSelection == nil
                            ? screenModel.selectedCharacter
                            : screenModel.selectedValue
                    )
                }
            }
        }
        .onChange(of: screenModel.selectedCharacter.selection) { old, new in
            screenModel.selectionDidChange(old, new, actions: actions)
        }
        .onChange(of: screenModel.selectedValue.selection) { old, new in
            screenModel.valueSelectionDidChange(old, new, root: root)
        }
    }
}

#Preview("Battle Round", traits: .mockData) {
    let model = BattleRoundPreviewData.model()
    BattleRoundView(model: model, actions: .preview(model: model))
}
