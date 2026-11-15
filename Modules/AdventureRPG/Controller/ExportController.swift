// @copyright André Trettin

import CoreRPG
import Foundation
import AudioRPG
import DiceRPG
import MapRPG
import PdfRPG
import WeatherRPG
import PhotoRPG
import RuleRPG
import SpaceRPG
import TableRPG
import CharacterRPG
import os.log

struct ExportController: Sendable {
    @MainActor init(rootManager: RootManager? = nil, root: AdventureRootModel, itemController: ItemController) {
        self.rootManager = rootManager
        self.root = root
        self.itemController = itemController
    }

    // Adventure is the hub itself, so its own hubControllable (for ExportControllable's
    // hub requirement) is just a lazy reference back to itself, not the whole RootManager.
    var rootManager: RootManager?
    let root: AdventureRootModel
    let itemController: ItemController

    private var resolvedRootManager: RootManager {
        guard let rootManager else {
            preconditionFailure("Adventure ExportController requires rootManager to be set before use.")
        }
        return rootManager
    }
}

extension ExportController: ExportControllable {
    var hubControllable: any RootExportControllable { root }
    var itemControllable: any ItemControllable { itemController }
    
    // See CODE_AUDIT §9.5 — loops over the shared sibling list instead of a
    // hand-listed chain of 10 `.merge(other:)` calls (merge order doesn't matter here,
    // since every sibling contributes disjoint module keys).
    @MainActor public func exportingAll() -> ItemModuleIds {
        var itemIds = ItemModuleIds(dictionary: [itemController.config.module: itemController.itemDataModel.items.filter { itemController.itemSync(for: $0)?.isHidden != true }])
        for sibling in root.siblingModuleRoots {
            itemIds.merge(other: sibling.exportControllable.exportingAll())
        }
        return itemIds
    }
    
    @MainActor public func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var audioIds: Set<UUID> = []
        var diceIds: Set<UUID> = []
        var mapIds: Set<UUID> = []
        var pdfIds: Set<UUID> = []
        var photoIds: Set<UUID> = []
        var ruleIds: Set<UUID> = []
        var spaceIds: Set<UUID> = []
        var weatherIds: Set<UUID> = []
        var tableIds: Set<UUID> = []
        var valueIds: Set<UUID> = []

        let results = bfsExportResults(seedIds: itemIds.ids[itemController.config.module, default: []]) { id in
            guard let item = itemController.itemSync(for: id) else { return nil }

            if let photoId = item.photoId, resolvedRootManager.photoRoot.linkControllable.validateLink(itemId: photoId) {
                photoIds.insert(photoId)
            }

            // The Characters the game master puts at the table travel with the adventure.
            for tablePlayer in item.tablePlayers
            where resolvedRootManager.characterRoot.linkControllable.validateLink(itemId: tablePlayer.characterId) {
                valueIds.insert(tablePlayer.characterId)
            }

            if item.specialCategory {
                return item.entries.compactMap { entryId in
                    itemController.itemSync(for: entryId.childId) != nil ? entryId.childId : nil
                }
            }

            var childIds: [UUID] = []
            // The hidden group adventure an entry stands for travels with it: its entry text is
            // only a copy, the receiver reads name and text from the group. See CODE_AUDIT_26 §5.3.
            for entry in item.entries {
                if let groupId = entry.adventureId, itemController.itemSync(for: groupId) != nil {
                    childIds.append(groupId)
                }
            }
            let links = item.entries.flatMap { LinkReplaceController.links(for: $0.content) }

            links.forEach {
                switch $0.module {
                case .adventure:
                    childIds.append($0.itemId)
                case .audio:
                    if resolvedRootManager.audioRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        audioIds.insert($0.itemId)
                    }
                case .dice:
                    if resolvedRootManager.diceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        diceIds.insert($0.itemId)
                    }
                case .map:
                    if resolvedRootManager.mapRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        mapIds.insert($0.itemId)
                    }
                case .pdf:
                    if resolvedRootManager.pdfRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        pdfIds.insert($0.itemId)
                    }
                case .photo:
                    if resolvedRootManager.photoRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        photoIds.insert($0.itemId)
                    }
                case .rule:
                    if resolvedRootManager.ruleRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        ruleIds.insert($0.itemId)
                    }
                case .space:
                    if resolvedRootManager.spaceRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        spaceIds.insert($0.itemId)
                    }
                case .table:
                    if resolvedRootManager.tableRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        tableIds.insert($0.itemId)
                    }
                case .value:
                    if resolvedRootManager.characterRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        valueIds.insert($0.itemId)
                    }
                case .weather:
                    if resolvedRootManager.weatherRoot.linkControllable.validateLink(itemId: $0.itemId) {
                        weatherIds.insert($0.itemId)
                    }
                default:
                    Logger.exportController.error("Adventure \(item.name, privacy: .private) export is not handling link \(String(describing: $0), privacy: .private)")
                }
            }
            return childIds
        }

        var allIds = finalizeExportResults(results, into: itemIds)
        // See CODE_AUDIT §9.5 — collapses 9 hand-copied `let newXIds = ...; allIds.merge(other: newXIds)`
        // pairs into a loop (merge order doesn't matter — each contributes disjoint module keys).
        let idsByModuleRoot: [(any ExportControllable, Set<UUID>)] = [
            (resolvedRootManager.audioRoot.exportControllable, audioIds),
            (resolvedRootManager.diceRoot.exportControllable, diceIds),
            (resolvedRootManager.mapRoot.exportControllable, mapIds),
            (resolvedRootManager.pdfRoot.exportControllable, pdfIds),
            (resolvedRootManager.photoRoot.exportControllable, photoIds),
            (resolvedRootManager.ruleRoot.exportControllable, ruleIds),
            (resolvedRootManager.spaceRoot.exportControllable, spaceIds),
            (resolvedRootManager.tableRoot.exportControllable, tableIds),
            (resolvedRootManager.characterRoot.exportControllable, valueIds),
            (resolvedRootManager.weatherRoot.exportControllable, weatherIds)
        ]
        for (exportControllable, ids) in idsByModuleRoot {
            allIds.merge(other: exportControllable.exporting(ids: ids))
        }
        return allIds
    }
    
    // Was a fragile chain of hand-numbered `ids1...ids9` variables, one per sibling root in
    // a fixed order — adding/removing a module meant renumbering every subsequent variable.
    // Rule is deliberately excluded here (exported last via `finalExport`), matching
    // `siblingModuleRootsExcludingRule`'s doc. See CODE_AUDIT §9.5.
    public func additionalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds {
        var currentIds = itemIds
        for sibling in root.siblingModuleRootsExcludingRule {
            currentIds = try await sibling.exportControllable.export(itemIds: currentIds, into: outputStream, exportModel: exportModel)
        }
        return currentIds
    }

    public func finalExport(itemIds: ItemModuleIds, stream outputStream: OutputStream, exportModel: ItemDataExportModel) async throws -> ItemModuleIds {
        try await resolvedRootManager.ruleRoot.exportControllable.export(
            itemIds: itemIds,
            into: outputStream,
            exportModel: exportModel
        )
    }
}
