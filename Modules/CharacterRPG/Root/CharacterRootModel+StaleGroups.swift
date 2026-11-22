// @copyright André Trettin

import CoreRPG
import Foundation
import os.log

/// A group item (`groupHidden`, owned by `ownerId` through `groupId`) that no entry points to any
/// more. A newer import that turned the group entry into a plain one left it behind, hidden and
/// reachable by nobody. See `ImportControllable.removeStaleGroups` for the import-time fix.
struct StaleGroup: Equatable {
    let id: UUID
    let name: String
    let ownerId: UUID
    let ownerName: String
    /// The groups nested in this one (reachable through its entries), which are stale with it.
    let nestedIds: [UUID]
}

extension CharacterRootModel {
    /// The stale groups of the library. Read only: nothing is changed.
    ///
    /// A group is stale when it is hidden as a group, has no folder parent, names a live owner and
    /// no item of the library (trashed ones included, to stay on the safe side) has an entry whose
    /// `valueId` is that group.
    func staleGroups() async -> [StaleGroup] {
        var models: [UUID: ValueModel] = [:]
        var referencedIds: Set<UUID> = []
        for id in itemController.itemDataModel.items {
            guard let model = await itemController.item(for: id) else { continue }
            models[id] = model
            referencedIds.formUnion(model.entries.compactMap(\.valueId))
        }

        var result: [StaleGroup] = []
        for (id, model) in models where !referencedIds.contains(id) {
            guard model.displayState == DisplayStateMask.groupHidden.rawValue,
                  model.parentId == nil,
                  !model.isHidden,
                  let ownerId = model.groupId,
                  let owner = models[ownerId],
                  !owner.isHidden else { continue }
            result.append(StaleGroup(
                id: id,
                name: model.name,
                ownerId: ownerId,
                ownerName: owner.name,
                nestedIds: Self.nestedGroupIds(of: model, in: models)
            ))
        }
        return result.sorted { $0.id.uuidString < $1.id.uuidString }
    }

    /// Every group reachable from `model` through entries, without `model` itself.
    private static func nestedGroupIds(of model: ValueModel, in models: [UUID: ValueModel]) -> [UUID] {
        var visited: Set<UUID> = [model.id]
        var ordered: [UUID] = []
        var queue = model.entries.compactMap(\.valueId)
        while let next = queue.popLast() {
            guard visited.insert(next).inserted, let nested = models[next] else { continue }
            ordered.append(next)
            queue.append(contentsOf: nested.entries.compactMap(\.valueId))
        }
        return ordered
    }

    /// Deletes the stale groups and logs each one. `delete` takes the groups nested in a group
    /// along, so only the stale roots are deleted. A summary line is always written, so a run
    /// without stale groups shows as `0`.
    func removeStaleGroups() async {
        let groups = await staleGroups()
        let nestedCount = groups.reduce(0) { $0 + $1.nestedIds.count }
        Logger.validateRepair.info("stale groups: deleting \(groups.count, privacy: .public) groups, \(nestedCount, privacy: .public) nested groups of them")
        for group in groups {
            Logger.validateRepair.info("deleting stale group \(group.id.uuidString, privacy: .public) \(group.name, privacy: .private) owner \(group.ownerId.uuidString, privacy: .public) \(group.ownerName, privacy: .private) nested \(group.nestedIds.count, privacy: .public)")
            await editController.delete(itemId: group.id)
        }
    }
}
