// @copyright André Trettin

import CharacterRPG
import CoreRPG
import Foundation
import MapRPG
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
        controller: BattleRoundController
    ) {
        guard oldSelection != newSelection,
              let combatantId = pendingCharacterCombatantId,
              let characterId = newSelection.first?.itemId else { return }
        controller.assignCharacter(combatantId, characterId)
        pendingCharacterCombatantId = nil
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
        if case .selection = presentation { presentation = nil }
    }

    func valueSelectionDidChange(
        _ oldSelection: [WindowItemSelection],
        _ newSelection: [WindowItemSelection],
        controller: BattleRoundController
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
                controller: controller
            )
        case let .combatant(combatantId, kind):
            _ = controller.assignValueEntry(
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
        controller: BattleRoundController,
        scenesManager: ScenesManager
    ) {
        if let sheet = BattleCharacterSheetFactory(characterRoot: controller.root.characterRoot).presentation(for: combatant) {
            presentation = .sheet(sheet)
            return
        }
        pendingCharacterCombatantId = combatant.id
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
#if os(macOS)
        controller.root.characterRoot.itemSelectionModel = selectedCharacter
        scenesManager.openWindow(SceneId.sceneId(for: .value))
#else
        presentation = .selection(combatant.id)
#endif
    }

    func selectConfiguredValue(
        _ kind: BattleValueKind,
        controller: BattleRoundController,
        scenesManager: ScenesManager
    ) {
        pendingValueSelection = .setting(kind)
        presentValueSelection(onlyChildrenFrom: nil, controller: controller, scenesManager: scenesManager)
    }

    func selectHitPoints(
        _ combatant: BattleCombatant,
        controller: BattleRoundController,
        scenesManager: ScenesManager
    ) {
        guard let sourceCharacterId = combatant.sourceCharacterId else {
            showCharacterSheet(combatant, controller: controller, scenesManager: scenesManager)
            return
        }
        pendingValueSelection = .combatant(combatantId: combatant.id, kind: .hitPoints)
        presentValueSelection(
            onlyChildrenFrom: sourceCharacterId,
            controller: controller,
            scenesManager: scenesManager
        )
    }

    func useDroppedConfiguredValue(
        _ value: LinkCharacterData,
        kind: BattleValueKind,
        controller: BattleRoundController
    ) {
        guard let entryId = value.entryId else { return }
        applySettingEntry(
            characterId: value.itemId,
            entryId: entryId,
            kind: kind,
            controller: controller
        )
    }

    func refreshConfiguredValues(controller: BattleRoundController) {
        controller.refreshConfiguredValues()
    }

    private func presentValueSelection(
        onlyChildrenFrom characterId: UUID?,
        controller: BattleRoundController,
        scenesManager: ScenesManager
    ) {
        selectedValue.onlyChildrenFrom = characterId
        selectedValue.onlyEntrySelection = true
        selectedValue.resetSelection(itemId: nil, entryId: nil)
#if os(macOS)
        controller.root.characterRoot.itemSelectionModel = selectedValue
        scenesManager.openWindow(SceneId.sceneId(for: .value))
#else
        presentation = .selection(UUID())
#endif
    }

    private func applySettingEntry(
        characterId: UUID,
        entryId: UUID,
        kind: BattleValueKind,
        controller: BattleRoundController
    ) {
        guard let entry = controller.root.characterRoot.valueGameControllable.gameEntry(
            characterId: characterId,
            entryId: entryId
        ) else { return }
        controller.root.mapRoot.mapGameControllable.battleRoundSettings.addName(entry.name, for: kind)
        refreshConfiguredValues(controller: controller)
    }
}

enum PendingValueSelection {
    case setting(BattleValueKind)
    case combatant(combatantId: UUID, kind: BattleValueKind)
}
