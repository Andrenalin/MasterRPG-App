// @copyright André Trettin

import CoreRPG
import Foundation

extension GameController {
    /// Deterministic identity of the recursive Value graph exported for a
    /// player's Character. Asset identifiers are already represented by each
    /// `ValueModel.version`; file bytes and local availability are not.
    @MainActor
    func networkVersion(for itemId: UUID) async -> Int {
        var pendingIds = [itemId]
        var visitedIds: Set<UUID> = []
        var components: [CharacterPackageVersion.Component] = []

        while let currentId = pendingIds.popLast() {
            guard visitedIds.insert(currentId).inserted else { continue }
            guard let value = itemController.itemSync(for: currentId) else {
                components.append(.init(id: currentId, version: 0))
                continue
            }

            components.append(.init(id: value.id, version: value.version))
            let linkedValueIds = if value.specialCategory {
                value.entries.map(\.childId)
            } else {
                value.entries.compactMap(\.valueId)
            }
            pendingIds.append(contentsOf: linkedValueIds)
        }

        return CharacterPackageVersion.digest(components)
    }
}

private enum CharacterPackageVersion {
    struct Component: Codable, Sendable {
        let id: UUID
        let version: Int
    }

    static func digest(_ components: [Component]) -> Int {
        let canonical = components.sorted { $0.id.uuidString < $1.id.uuidString }
        return StableVersionDigest.digest(canonical)
    }
}
