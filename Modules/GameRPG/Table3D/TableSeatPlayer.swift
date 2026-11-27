// @copyright André Trettin

import Foundation

/// A player sitting at a seat of the 3D table: the player id their game messages carry, which the
/// dice are looked up by, and the name shown. `id` is `nil` only for a group known by its roll's
/// name alone (a guest, a master without a table). See CODE_AUDIT_29 §5.7.
struct TableSeatPlayer: Equatable, Sendable {
    let id: UUID?
    let name: String

    /// Sorted by name, then by id, so every device lists a seat's players the same way.
    static func displayOrder(_ players: [TableSeatPlayer]) -> [TableSeatPlayer] {
        players.sorted {
            ($0.name, $0.id?.uuidString ?? "") < ($1.name, $1.id?.uuidString ?? "")
        }
    }
}
