// @copyright André Trettin

import CoreRPG
import Foundation

@MainActor
private final class RuleExportRootReference: Sendable {
    var rootManager: RootManager?
}

struct ExportController: Sendable {
    @MainActor
    init(itemController: ItemController) {
        self.itemController = itemController
        exportModel = ExportModel()
        rootReference = RuleExportRootReference()
    }

    let itemController: ItemController
    let exportModel: ExportModel
    private let rootReference: RuleExportRootReference

    @MainActor
    private var resolvedRootManager: RootManager {
        guard let rootManager = rootReference.rootManager else {
            preconditionFailure("RuleRPG export requires RootManager after setup.")
        }
        return rootManager
    }

    @MainActor
    func setUp(rootManager: RootManager) {
        rootReference.rootManager = rootManager
    }
}

extension ExportController: ExportModelBacked {
    var itemControllable: any ItemControllable { itemController }

    @MainActor
    func exportingAll() -> ItemModuleIds {
        ItemModuleIds(dictionary: [
            .rule: itemController.itemDataModel.items.filter {
                itemController.itemSync(for: $0)?.displayState != DisplayStateMask.totalHidden.rawValue
            }
        ])
    }

    @MainActor
    func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var pending = itemIds.ids[.rule, default: []]
        var pendingIDs = Set(pending)
        var exported: Set<UUID> = []
        var linkedIDs: [NetworkModules: Set<UUID>] = [:]
        let rootManager = resolvedRootManager

        while let id = pending.popLast() {
            pendingIDs.remove(id)
            guard !exported.contains(id), let item = itemController.itemSync(for: id) else { continue }
            exported.insert(id)

            if item.specialCategory {
                for childID in item.entries.map(\.childId) {
                    guard !exported.contains(childID),
                          itemController.itemSync(for: childID) != nil,
                          pendingIDs.insert(childID).inserted else { continue }
                    pending.append(childID)
                }
            }

            var links = LinkReplaceController.links(for: item.description)
            if !item.specialCategory {
                links.append(contentsOf: item.entries.flatMap { entry in
                    entry.links(for: entry.content)
                })
            }

            for link in links {
                guard let destinationRoot = rootManager.rootModel(for: link.module),
                      destinationRoot.linkControllable.validateLink(itemId: link.itemId) else {
                    continue
                }

                switch link.module {
                case .rule:
                    guard !exported.contains(link.itemId),
                          pendingIDs.insert(link.itemId).inserted else { continue }
                    pending.append(link.itemId)
                case .adventure, .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather:
                    linkedIDs[link.module, default: []].insert(link.itemId)
                case .editor, .game, .generator, .none, .search, .setting:
                    continue
                }
            }
        }

        let partialFolders = exportingFolder(results: &exported)
        var result = itemIds
        result.ids[.rule] = Array(exported)
        result.mergePartial(ids: Array(partialFolders), for: .rule)

        // Adventure owns the aggregate export graph and can itself reference Rules. Keep
        // direct Adventure destinations without recursing back through its exporter.
        if let adventureIDs = linkedIDs[.adventure], !adventureIDs.isEmpty {
            var fullAdventureIDs = adventureIDs
            if let adventureRoot = rootManager.rootModel(for: .adventure) {
                let partialAdventureIDs = adventureRoot.exportControllable.exportingFolder(
                    results: &fullAdventureIDs
                )
                result.mergePartial(ids: Array(partialAdventureIDs), for: .adventure)
            }
            result.merge(ids: Array(fullAdventureIDs), for: .adventure)
        }

        // The remaining supported destinations form the acyclic side of the export graph.
        // Delegate to each module so its own leaf dependencies and partial folders survive.
        let expandableModules: [NetworkModules] = [
            .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather,
        ]
        for module in expandableModules {
            let ids = linkedIDs[module, default: []]
            guard !ids.isEmpty,
                  let destinationRoot = rootManager.rootModel(for: module) else { continue }
            result.merge(other: destinationRoot.exportControllable.exporting(ids: ids))
        }
        return result
    }
}
