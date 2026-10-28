// @copyright André Trettin

#if !os(tvOS)

import AdventureRPG
import AppIntents
import AudioRPG
import CharacterRPG
import DiceRPG
import GeneratorRPG
import MapRPG
import PdfRPG
import PhotoRPG
import RolePlayGameKit
import RuleRPG
import SpaceRPG
import TableRPG
import WeatherRPG

@MainActor
enum MasterRPGSpotlightIndexer {
    /// Tells every module which entity type its donations name, so trashing or purging an item
    /// deletes them, and how its items are exported as text. See CODE_AUDIT_AppIntents §4.4,
    /// CODE_AUDIT_AppIntents3 §4.1.
    static func registerIntentSupport(appModel: AppModel) {
        AdventureIntentSupport.registerIntentSupport(root: appModel.adventureRoot)
        AudioIntentSupport.registerIntentSupport(root: appModel.audioRoot)
        CharacterIntentSupport.registerIntentSupport(root: appModel.characterRoot)
        DiceIntentSupport.registerIntentSupport(root: appModel.diceRoot)
        GeneratorIntentSupport.registerIntentSupport(root: appModel.generatorRoot)
        MapIntentSupport.registerIntentSupport(root: appModel.mapRoot)
        PdfIntentSupport.registerIntentSupport(root: appModel.pdfRoot)
        PhotoIntentSupport.registerIntentSupport(root: appModel.photoRoot)
        RuleIntentSupport.registerIntentSupport(root: appModel.ruleRoot)
        SpaceIntentSupport.registerIntentSupport(root: appModel.spaceRoot)
        TableIntentSupport.registerIntentSupport(root: appModel.tableRoot)
        WeatherIntentSupport.registerIntentSupport(root: appModel.weatherRoot)
    }

    /// Indexes what changed since the last pass; a module without changes costs nothing. No App
    /// Shortcut phrase takes a parameter any more, so there is no parameter cache to refresh.
    /// See CODE_AUDIT_AppIntents §7.1, CODE_AUDIT_Since_3.0.1 §4.3.
    static func reindexChanged(appModel: AppModel) async {
        await AdventureIntentSupport.reindexChanged(root: appModel.adventureRoot)
        await AudioIntentSupport.reindexChanged(root: appModel.audioRoot)
        await CharacterIntentSupport.reindexChanged(root: appModel.characterRoot)
        await DiceIntentSupport.reindexChanged(root: appModel.diceRoot)
        await GeneratorIntentSupport.reindexChanged(root: appModel.generatorRoot)
        await MapIntentSupport.reindexChanged(root: appModel.mapRoot)
        await PdfIntentSupport.reindexChanged(root: appModel.pdfRoot)
        await PhotoIntentSupport.reindexChanged(root: appModel.photoRoot)
        await RuleIntentSupport.reindexChanged(root: appModel.ruleRoot)
        await SpaceIntentSupport.reindexChanged(root: appModel.spaceRoot)
        await TableIntentSupport.reindexChanged(root: appModel.tableRoot)
        await WeatherIntentSupport.reindexChanged(root: appModel.weatherRoot)
    }
}

#endif
