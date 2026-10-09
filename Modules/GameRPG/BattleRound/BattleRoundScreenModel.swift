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
    init(model: BattleRoundModel) {
        self.model = model
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

    var presentation: BattleRoundPresentation?
    var isConfigurationExpanded = false
    var isInspectorPresented = false

    let selectedCharacter: ItemSelectionModel
    let selectedValue: ItemSelectionModel

    private(set) var pendingCharacterCombatantId: UUID?
    private(set) var pendingValueSelection: PendingValueSelection?

    private let model: BattleRoundModel

    /// The id of the card whose attacker has the turn (a card's id is its
    /// entry's id). The list scrolls it to the top when the turn moves on.
    var activeCardId: UUID? {
        model.activeEntry?.id
    }

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
        resetCharacterSelectionState()
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

        resetValueSelectionState()
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
        // Switching back to character-assignment mode must drop any pending
        // value-selection state, or the inspector stays stuck showing the
        // previous combatant's value list instead of the full character list.
        resetValueSelectionState()
        presentInspectorOrSelection(id: combatant.id)
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

    func selectInitiative(
        _ combatant: BattleCombatant,
        controller: BattleRoundController,
        scenesManager: ScenesManager
    ) {
        guard let sourceCharacterId = combatant.sourceCharacterId else {
            showCharacterSheet(combatant, controller: controller, scenesManager: scenesManager)
            return
        }
        pendingValueSelection = .combatant(combatantId: combatant.id, kind: .initiative)
        presentValueSelection(
            onlyChildrenFrom: sourceCharacterId,
            controller: controller,
            scenesManager: scenesManager
        )
    }

    @discardableResult
    func useDroppedConfiguredValue(
        _ value: LinkCharacterData,
        kind: BattleValueKind,
        controller: BattleRoundController
    ) -> Bool {
        guard let entryId = value.entryId else { return false }
        return applySettingEntry(
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
        // Mirror of the reset above: leaving character-assignment mode.
        resetCharacterSelectionState()
        presentInspectorOrSelection(id: pendingValueSelection?.presentationId ?? UUID())
    }

    /// Clears the character-assignment selection flow — used both when a
    /// character assignment completes (`selectionDidChange`) and when
    /// switching into value-assignment mode, where it mirrors
    /// `resetValueSelectionState()`. See CODE_AUDIT §9.1.
    private func resetCharacterSelectionState() {
        pendingCharacterCombatantId = nil
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
    }

    /// Clears the value-assignment selection flow — used both when a value
    /// assignment completes (`valueSelectionDidChange`) and when switching
    /// into character-assignment mode, where it mirrors
    /// `resetCharacterSelectionState()`. See CODE_AUDIT §9.1.
    private func resetValueSelectionState() {
        pendingValueSelection = nil
        selectedValue.onlyChildrenFrom = nil
        selectedValue.resetSelection(itemId: nil, entryId: nil)
    }

    /// The one place that decides "inspector on macOS, sheet elsewhere" —
    /// `showCharacterSheet` and `presentValueSelection` used to each hand-copy
    /// this branch. See CODE_AUDIT §9.1.
    private func presentInspectorOrSelection(id: UUID) {
#if os(macOS)
        isInspectorPresented = true
#else
        presentation = .selection(id)
#endif
    }

    @discardableResult
    private func applySettingEntry(
        characterId: UUID,
        entryId: UUID,
        kind: BattleValueKind,
        controller: BattleRoundController
    ) -> Bool {
        guard let entry = controller.root.characterRoot.valueGameControllable.gameEntry(
            characterId: characterId,
            entryId: entryId
        ) else { return false }
        controller.root.mapRoot.mapGameControllable.battleRoundSettings.addName(entry.name.withoutLink(), for: kind)
        refreshConfiguredValues(controller: controller)
        return true
    }
}

enum PendingValueSelection {
    case setting(BattleValueKind)
    case combatant(combatantId: UUID, kind: BattleValueKind)

    /// A stable id for `.selection`'s `Identifiable` sheet-item requirement.
    /// Not otherwise read anywhere — the list actually shown is driven by
    /// `pendingValueSelection`/`selectedCharacter`/`selectedValue`, not by
    /// this id — but it used to be a fresh random `UUID()` on every call,
    /// inconsistent with `showCharacterSheet`'s use of the combatant's own
    /// stable id for the same `.selection` case. See CODE_AUDIT §9.2.
    var presentationId: UUID {
        switch self {
        case .combatant(let combatantId, _):
            combatantId
        case .setting(let kind):
            kind.settingsPresentationId
        }
    }
}

private extension BattleValueKind {
    /// A fixed, stable id per kind, used only by `PendingValueSelection.presentationId`.
    var settingsPresentationId: UUID {
        switch self {
        case .initiative:
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1))
        case .hitPoints:
            UUID(uuid: (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 2))
        }
    }
}
