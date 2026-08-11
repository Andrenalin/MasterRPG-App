// @copyright André Trettin

import CoreRPG
import CryptoKit
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
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(canonical) else { return 1 }

        let digest = SHA256.hash(data: data)
        let rawValue = digest.prefix(8).reduce(UInt64(0)) { partialResult, byte in
            partialResult << 8 | UInt64(byte)
        }
        let version = Int(bitPattern: UInt(truncatingIfNeeded: rawValue))
        return version == 0 ? 1 : version
    }
}
