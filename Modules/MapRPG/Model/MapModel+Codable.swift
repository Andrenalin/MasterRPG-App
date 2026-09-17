// @copyright André Trettin

import CoreRPG
import Foundation

// Split out of MapModel.swift — see CODE_AUDIT §9.13. `Codable` itself
// (`CodingKeys` + `encode(to:)`) stays in MapModel.swift alongside the class
// declaration: it reads `@Observable`'s macro-synthesized private backing
// storage (`_name_`, `_description_`, ...) directly, bypassing observation
// tracking, and Swift's `private` only extends to same-file extensions.

extension MapModel: nonisolated Equatable, nonisolated Hashable {
    nonisolated public static func == (lhs: MapModel, rhs: MapModel) -> Bool {
        return assumeMainActorIsolated {
            lhs.id == rhs.id && lhs.isSame(rhs) && lhs.displayState == rhs.displayState

        }
    }

    nonisolated public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
}
