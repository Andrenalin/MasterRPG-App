// @copyright André Trettin

import AdventureRPG
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

/// The module root models' database maintenance operations (folder/hidden-state repair,
/// cross-module link validation, and orphaned-item cleanup). These are requirements of
/// `ItemRootControllable` itself, so this is only the name the app-wide maintenance sweeps
/// (`ValidateRepairController`, `AppModel.cleanDatabase`) use for "every module root".
/// See CODE_AUDIT §9.5.
typealias ModuleFolderRepairable = ItemRootControllable

extension AppModel {
    /// All module roots paired with their `NetworkModules` tag, ordered so that a module
    /// other content links *into* (adventure, the story hub) is processed last.
    var moduleFolderRepairSteps: [(module: NetworkModules, root: any ModuleFolderRepairable)] {
        [
            (.photo, photoRoot),
            (.rule, ruleRoot),
            (.audio, audioRoot),
            (.space, spaceRoot),
            (.pdf, pdfRoot),
            (.dice, diceRoot),
            (.weather, weatherRoot),
            (.table, tableRoot),
            (.value, characterRoot),
            (.map, mapRoot),
            (.adventure, adventureRoot),
        ]
    }
}
