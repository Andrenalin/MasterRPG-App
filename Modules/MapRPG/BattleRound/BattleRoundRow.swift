// @copyright André Trettin

import CoreRPG
import SwiftUI
import CharacterRPG

public struct BattleRoundView: View {
    public init(model: BattleRoundModel, actions: BattleRoundActions) {
        self.model = model
        self.actions = actions
    }

    let model: BattleRoundModel
    let actions: BattleRoundActions

    @Environment(MapRootModel.self) private var root
    @Environment(ScenesManager.self) private var scenesManager
    @State private var presentation: BattleRoundPresentation?
    @State private var pendingCharacterCombatantId: UUID?
    @State private var selectedCharacter = ItemSelectionModel(
        isSingleSelection: true,
        allowCollections: false
    )

    public var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                BattleRoundHeader(
                    isRunning: model.isRunning,
                    hasEntries: !model.entries.isEmpty,
                    round: model.roundCounter,
                    activeAttackerName: activeAttackerName,
                    initiativeOrder: model.initiativeOrder,
                    actions: actions
                )

                if model.isRunning, !model.entries.isEmpty {
                    BattleRoundList(
                        cards: model.cardPresentations,
                        actions: actions,
                        showCharacter: showCharacterSheet
                    )
                } else {
                    BattleRoundEmptyState(
                        isRunning: model.isRunning,
                        start: actions.start
                    )
                }
            }
            .navigationTitle(Text("Battle Round", bundle: .module))
            .battleInlineNavigationTitle()
        }
        .sheet(item: $presentation) { presentation in
            switch presentation {
            case .sheet(let sheet):
                BattleCharacterSheetPresentationView(presentation: sheet)
            case .selection:
                ManagedPresentationView {
                    root.viewController.characterSelection(
                        root: root,
                        selectionModel: selectedCharacter
                    )
                }
            }
        }
        .onChange(of: selectedCharacter.selection) { oldSelection, newSelection in
            selectionDidChange(oldSelection, newSelection)
        }
    }

    private var activeAttackerName: String? {
        guard let entry = model.activeEntry else { return nil }
        return model.attacker(for: entry)?.name
    }

    private func selectionDidChange(
        _ oldSelection: [WindowItemSelection],
        _ newSelection: [WindowItemSelection]
    ) {
        guard oldSelection != newSelection,
              let combatantId = pendingCharacterCombatantId,
              let characterId = newSelection.first?.itemId else {
            return
        }
        actions.assignCharacter(combatantId, characterId)
        pendingCharacterCombatantId = nil
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
        if case .selection = presentation {
            presentation = nil
        }
    }

    private func showCharacterSheet(_ combatant: BattleCombatant) {
        if let sheet = BattleCharacterSheetFactory(root: root).presentation(for: combatant) {
            presentation = .sheet(sheet)
            return
        }
        pendingCharacterCombatantId = combatant.id
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
#if os(macOS)
        root.characterRoot.itemSelectionModel = selectedCharacter
        scenesManager.openWindow(SceneId.sceneId(for: .value))
#else
        presentation = .selection(combatant.id)
#endif
    }
}
