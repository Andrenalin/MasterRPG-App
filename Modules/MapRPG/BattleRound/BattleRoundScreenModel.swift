// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import Observation
import SwiftUI

/// Coordinates all presentation state and selection flows for the battle round
/// UI. Presentation logic is isolated here so `BattleRoundView` stays a pure
/// layout/observation surface.
@MainActor @Observable
final class BattleRoundScreenModel {
    init(model: BattleRoundModel, layout: BattleRoundCardLayout) {
        self.model = model
        self.cardLayout = layout
        selectedCharacter = ItemSelectionModel(
            isSingleSelection: true,
            allowCollections: false
        )
        selectedValue = ItemSelectionModel(
            isSingleSelection: true,
            allowCollections: false,
            allowEntrySelection: true,
            onlyEntrySelection: true
        )
    }

    let cardLayout: BattleRoundCardLayout
    var presentation: BattleRoundPresentation?
    var isConfigurationExpanded = false

    let selectedCharacter: ItemSelectionModel
    let selectedValue: ItemSelectionModel

    private(set) var pendingCharacterCombatantId: UUID?
    private(set) var pendingValueSelection: PendingValueSelection?

    private let model: BattleRoundModel

    var activeAttackerName: String? {
        guard let entry = model.activeEntry else { return nil }
        return model.attacker(for: entry)?.name
    }

    func selectionDidChange(
        _ oldSelection: [WindowItemSelection],
        _ newSelection: [WindowItemSelection],
        actions: BattleRoundActions
    ) {
        guard oldSelection != newSelection,
              let combatantId = pendingCharacterCombatantId,
              let characterId = newSelection.first?.itemId else { return }
        actions.assignCharacter(combatantId, characterId)
        pendingCharacterCombatantId = nil
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
        if case .selection = presentation { presentation = nil }
    }

    func valueSelectionDidChange(
        _ oldSelection: [WindowItemSelection],
        _ newSelection: [WindowItemSelection],
        root: MapRootModel
    ) {
        guard oldSelection != newSelection,
              let target = pendingValueSelection,
              let selection = newSelection.first,
              let entryId = selection.entryId else { return }

        switch target {
        case .setting(let kind):
            applySettingEntry(
                characterId: selection.itemId,
                entryId: entryId,
                kind: kind,
                root: root
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
        if case .selection = presentation { presentation = nil }
    }

    func showCharacterSheet(
        _ combatant: BattleCombatant,
        root: MapRootModel,
        scenesManager: ScenesManager
    ) {
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

    func selectConfiguredValue(
        _ kind: BattleValueKind,
        root: MapRootModel,
        scenesManager: ScenesManager
    ) {
        pendingValueSelection = .setting(kind)
        presentValueSelection(onlyChildrenFrom: nil, root: root, scenesManager: scenesManager)
    }

    func selectHitPoints(
        _ combatant: BattleCombatant,
        root: MapRootModel,
        scenesManager: ScenesManager
    ) {
        guard let sourceCharacterId = combatant.sourceCharacterId else {
            showCharacterSheet(combatant, root: root, scenesManager: scenesManager)
            return
        }
        pendingValueSelection = .combatant(combatantId: combatant.id, kind: .hitPoints)
        presentValueSelection(
            onlyChildrenFrom: sourceCharacterId,
            root: root,
            scenesManager: scenesManager
        )
    }

    func useDroppedConfiguredValue(
        _ value: LinkCharacterData,
        kind: BattleValueKind,
        root: MapRootModel
    ) {
        guard let entryId = value.entryId else { return }
        applySettingEntry(
            characterId: value.itemId,
            entryId: entryId,
            kind: kind,
            root: root
        )
    }

    func refreshConfiguredValues(root: MapRootModel) {
        guard let mapId = model.mapId else { return }
        root.gameController.refreshBattleConfiguredValues(itemId: mapId)
    }

    private func presentValueSelection(
        onlyChildrenFrom characterId: UUID?,
        root: MapRootModel,
        scenesManager: ScenesManager
    ) {
        selectedValue.onlyChildrenFrom = characterId
        selectedValue.onlyEntrySelection = true
        selectedValue.resetSelection(itemId: nil, entryId: nil)
#if os(macOS)
        root.characterRoot.itemSelectionModel = selectedValue
        scenesManager.openWindow(SceneId.sceneId(for: .value))
#else
        presentation = .selection(UUID())
#endif
    }

    private func applySettingEntry(
        characterId: UUID,
        entryId: UUID,
        kind: BattleValueKind,
        root: MapRootModel
    ) {
        guard let entry = root.characterRoot.valueGameControllable.gameEntry(
            characterId: characterId,
            entryId: entryId
        ) else { return }
        switch kind {
        case .initiative:
            root.mapGameControllable.battleRoundSettings.initiativeName = entry.name
        case .hitPoints:
            root.mapGameControllable.battleRoundSettings.hitPointsName = entry.name
        }
        refreshConfiguredValues(root: root)
    }
}

enum PendingValueSelection {
    case setting(BattleValueKind)
    case combatant(combatantId: UUID, kind: BattleValueKind)
}
