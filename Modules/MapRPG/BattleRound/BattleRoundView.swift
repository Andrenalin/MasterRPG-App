// @copyright André Trettin

import CharacterRPG
import CoreRPG
import SwiftUI

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
    @State private var isConfigurationExpanded = false
    @State private var pendingCharacterCombatantId: UUID?
    @State private var pendingValueSelection: PendingValueSelection?
    @State private var selectedCharacter = ItemSelectionModel(
        isSingleSelection: true,
        allowCollections: false
    )
    @State private var selectedValue = ItemSelectionModel(
        isSingleSelection: true,
        allowCollections: false,
        allowEntrySelection: true,
        onlyEntrySelection: true
    )

    public var body: some View {
        ManagedNavigationStack(name: "BattleRound") {
            VStack(spacing: 0) {
                BattleRoundHeader(
                    isRunning: model.isRunning,
                    hasEntries: !model.entries.isEmpty,
                    round: model.roundCounter,
                    activeAttackerName: activeAttackerName,
                    initiativeOrder: model.initiativeOrder,
                    actions: actions,
                    isConfigurationExpanded: $isConfigurationExpanded
                )

                if isConfigurationExpanded {
                    BattleRoundSettingsView(
                        settings: root.mapGameControllable.battleRoundSettings,
                        actions: actions,
                        selectEntry: selectConfiguredValue,
                        useDroppedEntry: useDroppedConfiguredValue,
                        refresh: refreshConfiguredValues
                    )
                }
                
                ScrollView {
                    LazyVStack {
                        if model.isRunning, !model.entries.isEmpty {
                            BattleRoundList(
                                cards: model.cardPresentations,
                                actions: actions,
                                showCharacter: showCharacterSheet,
                                selectHitPoints: selectHitPoints
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
        .sheet(item: $presentation) { presentation in
            switch presentation {
            case .sheet(let sheet):
                BattleCharacterSheetPresentationView(presentation: sheet)
            case .selection:
                ManagedPresentationView {
                    root.viewController.characterSelection(
                        root: root,
                        selectionModel: pendingValueSelection == nil
                            ? selectedCharacter
                            : selectedValue
                    )
                }
            }
        }
        .onChange(of: selectedCharacter.selection) { oldSelection, newSelection in
            selectionDidChange(oldSelection, newSelection)
        }
        .onChange(of: selectedValue.selection) { oldSelection, newSelection in
            valueSelectionDidChange(oldSelection, newSelection)
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

    private func selectConfiguredValue(_ kind: BattleValueKind) {
        pendingValueSelection = .setting(kind)
        presentValueSelection(onlyChildrenFrom: nil)
    }

    private func selectHitPoints(_ combatant: BattleCombatant) {
        guard let sourceCharacterId = combatant.sourceCharacterId else {
            showCharacterSheet(combatant)
            return
        }
        pendingValueSelection = .combatant(
            combatantId: combatant.id,
            kind: .hitPoints
        )
        presentValueSelection(onlyChildrenFrom: sourceCharacterId)
    }

    private func presentValueSelection(onlyChildrenFrom characterId: UUID?) {
        selectedValue.onlyChildrenFrom = characterId
        selectedValue.resetSelection(itemId: nil, entryId: nil)
#if os(macOS)
        root.characterRoot.itemSelectionModel = selectedValue
        scenesManager.openWindow(SceneId.sceneId(for: .value))
#else
        presentation = .selection(UUID())
#endif
    }

    private func valueSelectionDidChange(
        _ oldSelection: [WindowItemSelection],
        _ newSelection: [WindowItemSelection]
    ) {
        guard oldSelection != newSelection,
              let target = pendingValueSelection,
              let selection = newSelection.first,
              let entryId = selection.entryId else {
            return
        }

        switch target {
        case .setting(let kind):
            applySettingEntry(
                characterId: selection.itemId,
                entryId: entryId,
                kind: kind
            )
        case let .combatant(combatantId, kind):
            guard let itemId = model.mapId else { break }
            _ = root.gameController.assignBattleValueEntry(
                itemId: itemId,
                combatantId: combatantId,
                sourceCharacterId: selection.itemId,
                sourceEntryId: entryId,
                kind: kind
            )
        }

        pendingValueSelection = nil
        selectedValue.onlyChildrenFrom = nil
        selectedValue.resetSelection(itemId: nil, entryId: nil)
        if case .selection = presentation {
            presentation = nil
        }
    }

    private func useDroppedConfiguredValue(
        _ value: LinkCharacterData,
        kind: BattleValueKind
    ) {
        guard let entryId = value.entryId else { return }
        applySettingEntry(
            characterId: value.itemId,
            entryId: entryId,
            kind: kind
        )
    }

    private func applySettingEntry(
        characterId: UUID,
        entryId: UUID,
        kind: BattleValueKind
    ) {
        guard let entry = root.characterRoot.valueGameControllable.gameEntry(
            characterId: characterId,
            entryId: entryId
        ) else {
            return
        }
        switch kind {
        case .initiative:
            root.mapGameControllable.battleRoundSettings.initiativeName = entry.name
        case .hitPoints:
            root.mapGameControllable.battleRoundSettings.hitPointsName = entry.name
        }
        refreshConfiguredValues()
    }

    private func refreshConfiguredValues() {
        guard let mapId = model.mapId else { return }
        root.gameController.refreshBattleConfiguredValues(itemId: mapId)
    }
}

private enum PendingValueSelection {
    case setting(BattleValueKind)
    case combatant(combatantId: UUID, kind: BattleValueKind)
}

#Preview("Battle Round", traits: .mockData) {
    let model = BattleRoundPreviewData.model()
    BattleRoundView(model: model, actions: .preview(model: model))
}
