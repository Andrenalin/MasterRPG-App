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

/// Common surface for the module root models' database maintenance operations
/// (folder/hidden-state repair, cross-module link validation, and orphaned-item cleanup).
///
/// Retroactively conformed here, in RolePlayGameKit, rather than in each module: only
/// app-wide maintenance sweeps (`ValidateRepairController`, `AppModel.cleanDatabase`) need
/// to treat every module uniformly, so the individual modules stay unaware of each other.
@MainActor
protocol ModuleFolderRepairable: ItemRootControllable {
    func checkFolders(reportModel: ValidateRepairModel) async
    func validateLinks(reportModel: ValidateRepairModel) async
    func itemDataCleanup() async
}

extension AdventureRootModel: ModuleFolderRepairable {}
extension AudioRootModel: ModuleFolderRepairable {}
extension CharacterRootModel: ModuleFolderRepairable {}
extension DiceRootModel: ModuleFolderRepairable {}
extension MapRootModel: ModuleFolderRepairable {}
extension PdfRootModel: ModuleFolderRepairable {}
extension PhotoRootModel: ModuleFolderRepairable {}
extension RuleRootModel: ModuleFolderRepairable {}
extension SpaceRootModel: ModuleFolderRepairable {}
extension TableRootModel: ModuleFolderRepairable {}
extension WeatherRootModel: ModuleFolderRepairable {}

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
