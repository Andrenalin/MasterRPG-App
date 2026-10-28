// @copyright André Trettin

import CharacterRPG
import CoreRPG
import DiceRPG
import SwiftUI

/// One quick dice slot. What it shows depends on where its dice come from: nothing yet, an entry
/// of the player's character, or a base dice chosen from the dice list. A dice dropped on the
/// slot, whatever it shows, replaces its dice.
struct QuickDiceSlotView: View {
    let root: GameRoot
    let index: Int

    @Environment(ScenesManager.self) private var scenesManager
    @Environment(\.appTheme) private var theme

    @State private var isPickerShown = false
    @State private var isDropTargeted = false
    @State private var pickerSelection = ItemSelectionModel()

    var body: some View {
        let slot = root.quickDiceSlots.slots[index]
        Group {
            switch slot?.source {
            case nil:
                QuickDiceEmptySlotView(index: index, choose: choose)
            case .entry(let itemId, let entryId):
                QuickDiceEntrySlotView(root: root, index: index, itemId: itemId, entryId: entryId)
            case .dice(let diceId):
                QuickDiceBaseDiceSlotView(root: root, index: index, diceId: diceId, manualValue: slot?.manualValue)
            }
        }
        // A slot that takes other dice starts over, with the game copy of its new dice.
        .id(slot?.source)
        .background {
            RoundedRectangle(cornerRadius: ResolvedAppTheme.elementCornerRadius, style: .continuous)
                .fill(isDropTargeted ? theme.dropTargetColor : .clear)
        }
        .dropDestination(for: .dice) { _, diceId, _ in
            root.quickDiceSlots.assign(QuickDiceSlot(source: .dice(diceId: diceId)), to: index)
        } isTargeted: { isTargeted in
            isDropTargeted = isTargeted
        }
        .contextMenu {
            if slot != nil {
                Button(action: choose) {
                    Label {
                        Text("Choose Dice", bundle: .module)
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                    }
                }
                Button(role: .destructive) {
                    root.quickDiceSlots.clear(index)
                } label: {
                    Label {
                        Text("Clear Slot", bundle: .module)
                    } icon: {
                        Image(systemName: "trash")
                    }
                }
            }
        }
#if os(iOS) || os(tvOS)
        .sheet(isPresented: $isPickerShown) {
            root.diceRoot.viewController.quickDicePickerView(root: root.diceRoot, selectionModel: pickerSelection)
        }
        .onChange(of: pickerSelection.selection) { _, selection in
            guard let diceId = selection.first?.itemId else { return }
            root.quickDiceSlots.assign(QuickDiceSlot(source: .dice(diceId: diceId)), to: index)
            pickerSelection.selection = []
            isPickerShown = false
        }
#endif
    }

    /// A sheet where the list fits in one, the dice link window to drag from where there are windows.
    private func choose() {
#if os(macOS) || os(visionOS)
        scenesManager.openWindow(SceneId(rawValue: NetworkModules.dice.linkWindowId))
#else
        isPickerShown = true
#endif
    }
}

private struct QuickDiceEmptySlotView: View {
    let index: Int
    let choose: () -> Void

    var body: some View {
        Button(action: choose) {
            VStack(spacing: 2) {
                Image(systemName: "plus.circle")
                    .imageScale(.large)
                Text("Add Dice", bundle: .module)
                    .font(.caption)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxWidth: .infinity, minHeight: 44)
        }
        .borderLessTVButtonStyle()
        .accessibilityLabel(Text("Add Dice to Slot \(index + 1)", bundle: .module))
    }
}

/// The dice of a character entry, as the sheet shows them. The value is the entry's calculated
/// value. Changing it is temporary: the entry's own value takes over again when it changes. The
/// override lives in the slots model, so the sheet's row of the same dice follows it.
private struct QuickDiceEntrySlotView: View {
    let root: GameRoot
    let index: Int
    let itemId: UUID
    let entryId: UUID

    var body: some View {
        let character = root.characterRoot.valueGameControllable
        if let gameDiceId = character.gameDiceId(itemId: itemId, entryId: entryId) {
            // Read in `body` so Observation follows every entry the formula links to.
            let linkedValue = character.diceCompareValue(itemId: itemId, entryId: entryId)
            let value = root.quickDiceSlots.effectiveValue(linkedValue: linkedValue, at: index)
            QuickDiceSlotContent(
                root: root,
                diceId: gameDiceId,
                resultCategory: ResultCategory(id: itemId, childId: entryId, module: .value)
            ) { newValue in
                root.quickDiceSlots.setOverride(newValue, linkedValue: linkedValue, at: index)
            }
            .onChange(of: linkedValue) {
                root.quickDiceSlots.linkedValueChanged(linkedValue, at: index)
            }
            .onChange(of: value, initial: true) {
                apply(value, to: gameDiceId)
            }
            .onChange(of: gameDiceId) {
                apply(value, to: gameDiceId)
            }
        } else {
            QuickDiceUnavailableSlotView()
        }
    }

    private func apply(_ value: Int?, to gameDiceId: UUID) {
        root.diceRoot.diceGameControllable.validateForValue(diceId: gameDiceId, compareValue: value)
    }
}

/// A base dice chosen from the dice list, played as a copy that keeps its own results. A dice
/// that is gone, or not loaded yet, shows as unavailable and is copied once it is there.
private struct QuickDiceBaseDiceSlotView: View {
    let root: GameRoot
    let index: Int
    let diceId: UUID
    let manualValue: Int?

    @State private var gameDiceId: UUID?

    var body: some View {
        let isAvailable = root.diceRoot.linkControllable.validateLink(itemId: diceId)
        Group {
            if !isAvailable {
                QuickDiceUnavailableSlotView()
            } else if let gameDiceId {
                // Shared as a plain dice roll, like a dice rolled from the dice list.
                QuickDiceSlotContent(root: root, diceId: gameDiceId, resultCategory: nil) { newValue in
                    root.quickDiceSlots.setManualValue(newValue, at: index)
                }
                .onChange(of: manualValue, initial: true) {
                    apply(to: gameDiceId)
                }
            } else {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .task(id: isAvailable ? diceId : nil) {
            guard isAvailable else { return }
            makeGameDice()
        }
    }

    /// Reuses the copy the slot already made, so a roll's result survives the view's recreation.
    private func makeGameDice() {
        let slots = root.quickDiceSlots
        let newId = root.diceRoot.diceGameControllable.createGameDice(
            for: diceId,
            gameDiceId: slots.gameDiceId(at: index, for: diceId)
        )
        slots.rememberGameDiceId(newId, at: index, for: diceId)
        gameDiceId = newId
    }

    private func apply(to gameDiceId: UUID) {
        root.diceRoot.diceGameControllable.validateForValue(diceId: gameDiceId, compareValue: manualValue)
    }
}

private struct QuickDiceSlotContent: View {
    let root: GameRoot
    let diceId: UUID
    let resultCategory: ResultCategory?
    let onValueChange: (Int) -> Void

    var body: some View {
        VStack(spacing: 4) {
            root.diceRoot.viewController.quickDiceRollButton(root: root.diceRoot, diceId: diceId, resultCategory: resultCategory)
            root.diceRoot.viewController.quickDiceValueButton(root: root.diceRoot, diceId: diceId, onValueChange: onValueChange)
        }
    }
}

private struct QuickDiceUnavailableSlotView: View {
    var body: some View {
        VStack(spacing: 2) {
            Image(systemName: "exclamationmark.triangle")
                .imageScale(.large)
            Text("Unavailable", bundle: .module)
                .font(.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .accessibilityElement(children: .combine)
    }
}
