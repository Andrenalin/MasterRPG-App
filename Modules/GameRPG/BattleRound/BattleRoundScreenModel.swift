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

    /// The modal list a Character or value is picked from. macOS never sets
    /// it: there the list is the window's inspector.
    var selectionPresentation: BattleRoundSelectionPresentation?
    var isConfigurationExpanded = false
    /// Ending a battle discards its turn order and rolls, so "End" asks first.
    var isEndConfirmationPresented = false
    /// The macOS inspector. Closing it ends a pending "choose" flow, so it
    /// does not come back still filtered to one Character's values.
    var isInspectorPresented = false {
        didSet {
            guard !isInspectorPresented else { return }
            cancelSelection()
        }
    }

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

    /// The attacker named in the header; not named while its pin is among the
    /// pins the list leaves out (`BattleRoundController.hiddenPinIds`).
    func activeAttackerName(hidingPins hiddenPinIds: Set<UUID>) -> String? {
        model.activeAttackerName(hidingPins: hiddenPinIds)
    }

    // MARK: - Selection

    /// What the selection list is currently open for.
    var selectionMode: BattleRoundSelectionMode {
        if let pendingValueSelection {
            switch pendingValueSelection {
            case .setting(let kind):
                return .pattern(kind)
            case let .combatant(combatantId, kind):
                return .value(kind, combatantName: model.combatant(id: combatantId)?.name)
            }
        }
        if let pendingCharacterCombatantId {
            return .character(combatantName: model.combatant(id: pendingCharacterCombatantId)?.name)
        }
        return .browse
    }

    /// The selection the list writes into: values while a value is being
    /// chosen, Characters otherwise.
    var activeSelectionModel: ItemSelectionModel {
        pendingValueSelection == nil ? selectedCharacter : selectedValue
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
        selectionPresentation = nil
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
        selectionPresentation = nil
    }

    /// Opens the Character list to pick one for a token that has none (or
    /// whose Character can no longer be shown).
    func chooseCharacter(for combatant: BattleCombatant) {
        pendingCharacterCombatantId = combatant.id
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
        // Switching back to character-assignment mode must drop any pending
        // value-selection state, or the list stays stuck showing the
        // previous combatant's values instead of the full character list.
        resetValueSelectionState()
        presentInspectorOrSelection(id: combatant.id)
    }

    func selectConfiguredValue(_ kind: BattleValueKind) {
        pendingValueSelection = .setting(kind)
        presentValueSelection(onlyChildrenFrom: nil)
    }

    func selectHitPoints(_ combatant: BattleCombatant) {
        selectValue(.hitPoints, for: combatant)
    }

    func selectInitiative(_ combatant: BattleCombatant) {
        selectValue(.initiative, for: combatant)
    }

    private func selectValue(_ kind: BattleValueKind, for combatant: BattleCombatant) {
        guard let sourceCharacterId = combatant.sourceCharacterId else {
            chooseCharacter(for: combatant)
            return
        }
        pendingValueSelection = .combatant(combatantId: combatant.id, kind: kind)
        presentValueSelection(onlyChildrenFrom: sourceCharacterId)
    }

    /// Leaves a pending "choose" flow without assigning anything: the list
    /// shows every Character again.
    func cancelSelection() {
        resetCharacterSelectionState()
        resetValueSelectionState()
    }

    // MARK: - Drops

    /// A value dragged onto a pattern row of the settings.
    @discardableResult
    func useDroppedConfiguredValue(
        _ value: LinkCharacterData,
        kind: BattleValueKind,
        controller: BattleRoundController
    ) -> Bool {
        guard let entryId = value.entryId,
              applySettingEntry(
                  characterId: value.itemId,
                  entryId: entryId,
                  kind: kind,
                  controller: controller
              ) else { return false }
        if pendingValueSelection == .setting(kind) {
            finishValueSelection()
        }
        return true
    }

    /// A value dragged onto a combatant's "Ini:" or "HP:". Finishes the
    /// matching pending "choose" flow, so the list does not stay filtered to
    /// that Character's values after the value has been assigned.
    @discardableResult
    func assignDroppedValue(
        _ value: LinkCharacterData,
        to combatantId: UUID,
        kind: BattleValueKind,
        controller: BattleRoundController
    ) -> Bool {
        guard let entryId = value.entryId,
              // `assignValueEntry` resolves `value.itemId` up through any
              // value-group ownership chain and rejects it unless that
              // resolves to this combatant's own source Character.
              controller.assignValueEntry(
                  combatantId: combatantId,
                  sourceCharacterId: value.itemId,
                  sourceEntryId: entryId,
                  kind: kind
              ) else { return false }
        if pendingValueSelection == .combatant(combatantId: combatantId, kind: kind) {
            finishValueSelection()
        }
        return true
    }

    /// A Character dragged onto a combatant's avatar.
    @discardableResult
    func assignDroppedCharacter(
        _ character: LinkCharacterData,
        to combatantId: UUID,
        controller: BattleRoundController
    ) -> Bool {
        guard controller.assignCharacter(combatantId, character.itemId) else { return false }
        if pendingCharacterCombatantId == combatantId {
            resetCharacterSelectionState()
            selectionPresentation = nil
        }
        return true
    }

    // MARK: - Battle lifecycle

    func requestEnd() {
        isEndConfirmationPresented = true
    }

    /// Called when the battle's running state changes. Returns `true` when
    /// the battle just ended, which closes its presentation (the window on
    /// macOS, the side panel elsewhere). Every pending flow belongs to the
    /// battle that ended and is dropped.
    func battleRunningDidChange(wasRunning: Bool, isRunning: Bool) -> Bool {
        guard wasRunning, !isRunning else { return false }
        cancelSelection()
        selectionPresentation = nil
        isEndConfirmationPresented = false
        return true
    }

    // MARK: - Turn order

    /// Moves the card `sourceId` to the position of the card `targetId`
    /// (a card's id is its entry's id): the drop of a dragged card.
    func moveCard(_ sourceId: UUID, onto targetId: UUID, controller: BattleRoundController) {
        guard sourceId != targetId,
              let sourceIndex = model.entries.firstIndex(where: { $0.id == sourceId }),
              let targetIndex = model.entries.firstIndex(where: { $0.id == targetId }) else {
            return
        }
        controller.moveEntries(
            IndexSet(integer: sourceIndex),
            Self.moveDestination(from: sourceIndex, to: targetIndex)
        )
    }

    /// Swaps a card with its neighbour one position earlier (`offset == -1`)
    /// or later (`offset == 1`): the non-drag way to reorder, for VoiceOver
    /// and Switch Control. A no-op at either end of the list.
    func moveCard(_ cardId: UUID, by offset: Int, controller: BattleRoundController) {
        guard let index = model.entries.firstIndex(where: { $0.id == cardId }) else { return }
        let targetIndex = index + offset
        guard model.entries.indices.contains(targetIndex), targetIndex != index else { return }
        controller.moveEntries(
            IndexSet(integer: index),
            Self.moveDestination(from: index, to: targetIndex)
        )
    }

    /// `IndexSet`-based moves expect a destination index that's one past `to`
    /// whenever the move is going forward.
    static func moveDestination(from: Int, to: Int) -> Int {
        to > from ? to + 1 : to
    }

    // MARK: - Private

    private func presentValueSelection(onlyChildrenFrom characterId: UUID?) {
        selectedValue.onlyChildrenFrom = characterId
        selectedValue.onlyEntrySelection = true
        selectedValue.resetSelection(itemId: nil, entryId: nil)
        // Mirror of the reset in `chooseCharacter`: leaving
        // character-assignment mode.
        resetCharacterSelectionState()
        presentInspectorOrSelection(id: pendingValueSelection?.presentationId ?? UUID())
    }

    private func finishValueSelection() {
        resetValueSelectionState()
        selectionPresentation = nil
    }

    /// Clears the character-assignment selection flow — used both when a
    /// character assignment completes and when switching into
    /// value-assignment mode, where it mirrors `resetValueSelectionState()`.
    private func resetCharacterSelectionState() {
        pendingCharacterCombatantId = nil
        selectedCharacter.resetSelection(itemId: nil, entryId: nil)
    }

    /// Clears the value-assignment selection flow — used both when a value
    /// assignment completes and when switching into character-assignment
    /// mode, where it mirrors `resetCharacterSelectionState()`.
    private func resetValueSelectionState() {
        pendingValueSelection = nil
        selectedValue.onlyChildrenFrom = nil
        selectedValue.resetSelection(itemId: nil, entryId: nil)
    }

    /// The one place that decides "inspector on macOS, sheet elsewhere".
    private func presentInspectorOrSelection(id: UUID) {
#if os(macOS)
        isInspectorPresented = true
#else
        selectionPresentation = BattleRoundSelectionPresentation(id: id)
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
        controller.refreshConfiguredValues()
        return true
    }
}

/// What the Character/value list is open for. `browse` is the plain list to
/// drag from; every other mode waits for one pick.
enum BattleRoundSelectionMode: Equatable {
    case browse
    case character(combatantName: String?)
    case value(BattleValueKind, combatantName: String?)
    /// A value whose name becomes a pattern in the battle settings.
    case pattern(BattleValueKind)
}

enum PendingValueSelection: Equatable {
    case setting(BattleValueKind)
    case combatant(combatantId: UUID, kind: BattleValueKind)

    /// A stable id for the selection sheet's `Identifiable` requirement.
    /// Not otherwise read anywhere — the list actually shown is driven by
    /// `pendingValueSelection`/`selectedCharacter`/`selectedValue`, not by
    /// this id — but it must not be a fresh random `UUID()` on every call:
    /// `chooseCharacter` uses the combatant's own stable id for the same
    /// sheet.
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
