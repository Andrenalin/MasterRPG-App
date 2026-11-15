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

    /// The rule as a player holds it: without the raw source payload, which the viewer never
    /// shows and which can be hundreds of KB per rule over the slowest channel. `version` is
    /// computed without it, so both copies agree. See CODE_AUDIT_26 §7.21.
    @MainActor
    func playerExportData(for itemId: UUID) throws -> Data? {
        guard let item = itemController.itemSync(for: itemId) else { return nil }
        let shared = item.copy()
        shared.sourcePayload = nil
        return try JSONCoding.encoder.encode(shared)
    }

    @MainActor
    func exportingAll() -> ItemModuleIds {
        ItemModuleIds(dictionary: [
            .rule: itemController.itemDataModel.items.filter {
                itemController.itemSync(for: $0)?.isHidden != true
            }
        ])
    }

    @MainActor
    func exporting(itemIds: ItemModuleIds) -> ItemModuleIds {
        var pending = itemIds.ids[.rule, default: []]
        var pendingIds = Set(pending)
        var exported: Set<UUID> = []
        var linkedIds: [NetworkModules: Set<UUID>] = [:]
        let rootManager = resolvedRootManager

        while let id = pending.popLast() {
            pendingIds.remove(id)
            guard !exported.contains(id), let item = itemController.itemSync(for: id) else { continue }
            exported.insert(id)

            if item.specialCategory {
                for childId in item.entries.map(\.childId) {
                    guard !exported.contains(childId),
                          itemController.itemSync(for: childId) != nil,
                          pendingIds.insert(childId).inserted else { continue }
                    pending.append(childId)
                }
            }

            var links = LinkReplaceController.links(for: item.description)
            if !item.specialCategory {
                links.append(contentsOf: item.entries.flatMap { entry in
                    LinkReplaceController.links(for: entry.content)
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
                          pendingIds.insert(link.itemId).inserted else { continue }
                    pending.append(link.itemId)
                case .adventure, .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather:
                    linkedIds[link.module, default: []].insert(link.itemId)
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
        if let adventureIds = linkedIds[.adventure], !adventureIds.isEmpty {
            var fullAdventureIds = adventureIds
            if let adventureRoot = rootManager.rootModel(for: .adventure) {
                let partialAdventureIds = adventureRoot.exportControllable.exportingFolder(
                    results: &fullAdventureIds
                )
                result.mergePartial(ids: Array(partialAdventureIds), for: .adventure)
            }
            result.merge(ids: Array(fullAdventureIds), for: .adventure)
        }

        // The remaining supported destinations form the acyclic side of the export graph.
        // Delegate to each module so its own leaf dependencies and partial folders survive.
        let expandableModules: [NetworkModules] = [
            .audio, .value, .dice, .map, .pdf, .photo, .space, .table, .weather,
        ]
        for module in expandableModules {
            let ids = linkedIds[module, default: []]
            guard !ids.isEmpty,
                  let destinationRoot = rootManager.rootModel(for: module) else { continue }
            result.merge(other: destinationRoot.exportControllable.exporting(ids: ids))
        }
        return result
    }
}
