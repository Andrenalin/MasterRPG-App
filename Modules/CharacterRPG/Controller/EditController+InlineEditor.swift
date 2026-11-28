// @copyright André Trettin

import CoreRPG
import Foundation

// MARK: - Inline Quick Editor
// Split out of EditController.swift — see CODE_AUDIT_Character §9.7.

extension EditController {
    @MainActor func entryValue(itemId: UUID, entryId: UUID?) -> String {
        guard let entryId else { return "" }
        return itemController.itemOrEmpty(for: itemId)[entryId].value
    }

    /// The entry's base ("max") and fully link-resolved current value — the
    /// same "base|modifier" convention (modifier *added* to base via a "+"
    /// substitution; either side possibly a markdown link several hops deep)
    /// `LinkController.calculate` already evaluates for every other display
    /// of this entry: the sheet row's own "= X" text (`linkText`), the
    /// Battle Round card, and `pin.healthPercent`. `valueCalculated`'s plain
    /// split-on-"|" is a poor match for a value that's itself a link with no
    /// local modifier yet (e.g. a hit-points entry set up as
    /// `[Lebenskraft](RPG://VALUES/...)`, no "|" at all) — it reads back "0"
    /// instead of the real current amount, which used to make this quick
    /// editor start every stepper adjustment from a false baseline and send
    /// a nonsensical value nowhere close to what the player actually typed.
    /// Returns `nil` when the entry can't be calculated or its base doesn't
    /// resolve to a number, so callers fall back to the plain stored text.
    @MainActor private func resolvedBaseAndCurrent(for entry: ValueEntryModel) -> (base: Double, current: Double)? {
        guard entry.canCalculate else { return nil }
        let baseText = ValueEntryModel.baseText(of: entry.value)
        let baseEntry = ValueEntryModel(id: entry.id, name: entry.name, type: entry.type, value: baseText)
        guard let resolvedBaseText = root.linkController.calculate(entry: baseEntry),
              let base = Double(resolvedBaseText) else {
            return nil
        }
        let current = root.linkController.calculate(entry: entry).flatMap(Double.init) ?? base
        return (base, current)
    }

    @MainActor func entryValueAsDecimal(itemId: UUID, entryId: UUID?) -> Double {
        guard let entryId else { return 0.0 }
        let entry = itemController.itemOrEmpty(for: itemId)[entryId]
        return resolvedBaseAndCurrent(for: entry)?.current ?? entry.valueDecimal
    }

    @MainActor func entryValueAsNumber(itemId: UUID, entryId: UUID?) -> Int {
        guard let entryId else { return 0 }
        let entry = itemController.itemOrEmpty(for: itemId)[entryId]
        guard let resolved = resolvedBaseAndCurrent(for: entry) else { return entry.valueNumber }
        return SheetNumberLimit.clamped(resolved.current)
    }

    @MainActor func entryValueAsSelected(itemId: UUID, entryId: UUID?) -> Bool {
        guard let entryId else { return false }
        return itemController.itemOrEmpty(for: itemId)[entryId].valueSelected
    }

    /// Shared guard/save/persist flow for the inline quick-editor's `updateValue`
    /// overloads. `mutate` receives a working copy of the entry and returns
    /// whether it actually changed it; a `false` return skips the save entirely.
    /// See CODE_AUDIT_Character §9.12.
    /// A forced save: during a game the changed entry reaches the library through the shared
    /// game-copy diff (`writeForcedEditOfGameCopy`), and undo reverts both copies. The module's
    /// own copy-to-library path (`saveGameDataToPermanent`) left undo reverting only game memory.
    /// See CODE_AUDIT_Edit_Save §5.23.
    @MainActor private func applyEntryUpdate(itemId: UUID, entryId: UUID?, message: String, mutate: (inout ValueEntryModel) -> Bool) {
        guard let entryId else { return }
        // The game reads a character from game memory (the player's entry update, the master's
        // battle state), so during a game the edit lands there too, as it did before.
        if itemController.itemDataModel.isGameMode, gameCopy(of: itemId) == nil,
           let library = itemController.itemSync(for: itemId, noGame: true)?.copy() as? ValueModel {
            itemController.replaceInGameMemory(model: library)
        }
        guard let item = editModel(for: itemId) else { return }
        var entry = item[entryId]
        guard mutate(&entry) else { return }
        item[entryId] = entry
        save(updated: item, message: message, forceSave: true)
    }

    @MainActor func updateValue(itemId: UUID, entryId: UUID?, decimal: Double) {
        applyEntryUpdate(itemId: itemId, entryId: entryId, message: String(localized: "Update decimal", bundle: .module)) { entry in
            guard let resolved = resolvedBaseAndCurrent(for: entry) else {
                guard entry.valueDecimal != decimal else { return false }
                entry.valueDecimal = decimal
                return true
            }
            guard resolved.current != decimal else { return false }
            let baseText = ValueEntryModel.baseText(of: entry.value)
            entry.value = "\(baseText)|\(ValueEntryModel.modifierText(decimal - resolved.base))"
            return true
        }
    }

    @MainActor func updateValue(itemId: UUID, entryId: UUID?, number: Int) {
        applyEntryUpdate(itemId: itemId, entryId: entryId, message: String(localized: "Update number", bundle: .module)) { entry in
            guard let resolved = resolvedBaseAndCurrent(for: entry) else {
                guard entry.valueNumber != number else { return false }
                entry.valueNumber = number
                return true
            }
            let number = SheetNumberLimit.clamped(number)
            guard SheetNumberLimit.clamped(resolved.current) != number else { return false }
            let baseText = ValueEntryModel.baseText(of: entry.value)
            let modifier = SheetNumberLimit.clamped(Double(number) - resolved.base)
            entry.value = "\(baseText)|\(modifier)"
            return true
        }
    }

    @MainActor func updateValue(itemId: UUID, entryId: UUID?, selected: Bool) {
        applyEntryUpdate(itemId: itemId, entryId: entryId, message: String(localized: "Update Selection", bundle: .module)) { entry in
            guard entry.valueSelected != selected else { return false }
            entry.toggleSelection()
            return true
        }
    }

    @MainActor func updateValue(itemId: UUID, entryId: UUID?, value: String) {
        applyEntryUpdate(itemId: itemId, entryId: entryId, message: String(localized: "Update value", bundle: .module)) { entry in
            guard entry.value != value else { return false }
            entry.value = value
            return true
        }
    }
}

// MARK: - QuickEntryEditor

extension EditController {
    func create(name: String, content: String) -> ValueEntryModel {
        ValueEntryModel(id: UUID(), name: name, type: termineType(content: content, currentType: .text), value: content)
    }

    @MainActor func merge(itemId: UUID, entries: [ValueEntryModel]) -> [ValueEntryModel] {
        entriesMatchedByName(itemId: itemId, entries: entries)
    }
    // `merge(itemId:entries:recoverEntries:forceSave:)` uses `EntryDataEditable`'s
    // shared default (see CODE_AUDIT_EditItem §9.2) — this module's behavior was
    // identical to the default, so the hand-copied override was removed.
}
