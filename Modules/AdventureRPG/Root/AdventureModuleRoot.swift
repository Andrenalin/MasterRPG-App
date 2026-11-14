// @copyright André Trettin

import AudioRPG
import CharacterRPG
import CoreRPG
import DiceRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import WeatherRPG

/// What AdventureRootModel needs from each sibling module root to reset, save, repair, and
/// toggle game mode across the whole database in one sweep. Every module root already has it
/// through `ItemRootControllable` (CODE_AUDIT §9.5), so this only names the role.
typealias AdventureModuleRoot = ItemRootControllable

extension AdventureRootModel {
    /// The 10 sibling module roots — excludes `self` (the adventure/story hub, handled
    /// separately by each caller) and `generatorRoot` (optional, tvOS-gated, and doesn't
    /// participate in folder repair or game-mode toggling the way the others do).
    // `nonisolated`: reads only `let` stored properties (already themselves
    // nonisolated-accessible, same as `root.audioRoot` elsewhere in this module) — lets
    // this be called from the non-`@MainActor` async functions that need it
    // (`ImportController.additionalImport`) without forcing a MainActor hop.
    nonisolated var siblingModuleRoots: [any AdventureModuleRoot] {
        [audioRoot, diceRoot, mapRoot, pdfRoot, photoRoot, ruleRoot, spaceRoot, tableRoot, characterRoot, weatherRoot]
    }

    /// `siblingModuleRoots` minus `ruleRoot` — Rule (the compendium/reference module) is
    /// deliberately exported/imported *last* (see `ExportController.finalExport`/
    /// `ImportController.finalImport`) rather than alongside the others.
    /// `ExportController.additionalExport` and `ImportController.additionalImport` loop over
    /// this instead of each hand-listing the same 9 sibling roots by name. Game start and reset
    /// use `siblingModuleRoots`, Rule included. See CODE_AUDIT §9.5, CODE_AUDIT_Folder §5.3.
    nonisolated var siblingModuleRootsExcludingRule: [any AdventureModuleRoot] {
        siblingModuleRoots.filter { !($0 is RuleRootModel) }
    }
}
