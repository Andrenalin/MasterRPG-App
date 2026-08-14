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

/// Common surface AdventureRootModel needs from each sibling module root to reset,
/// save, repair, and toggle game mode across the whole database in one sweep.
///
/// Retroactively conformed here (not in each module) since only the Adventure hub needs
/// to treat every module uniformly — Adventure is the one module that links to all others.
@MainActor
protocol AdventureModuleRoot: ItemRootControllable {
    func checkFolders(reportModel: ValidateRepairModel) async
    func validateLinks(reportModel: ValidateRepairModel) async
}

extension AudioRootModel: AdventureModuleRoot {}
extension CharacterRootModel: AdventureModuleRoot {}
extension DiceRootModel: AdventureModuleRoot {}
extension MapRootModel: AdventureModuleRoot {}
extension PdfRootModel: AdventureModuleRoot {}
extension PhotoRootModel: AdventureModuleRoot {}
extension RuleRootModel: AdventureModuleRoot {}
extension SpaceRootModel: AdventureModuleRoot {}
extension TableRootModel: AdventureModuleRoot {}
extension WeatherRootModel: AdventureModuleRoot {}

extension AdventureRootModel {
    /// The 10 sibling module roots — excludes `self` (the adventure/story hub, handled
    /// separately by each caller) and `generatorRoot` (optional, tvOS-gated, and doesn't
    /// participate in folder repair or game-mode toggling the way the others do).
    var siblingModuleRoots: [any AdventureModuleRoot] {
        [audioRoot, diceRoot, mapRoot, pdfRoot, photoRoot, ruleRoot, spaceRoot, tableRoot, characterRoot, weatherRoot]
    }
}
