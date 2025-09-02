// @copyright André Trettin

import Foundation

struct DieModel: Equatable, Hashable, Identifiable, Codable, Sendable {
    let id: UUID
    let die: RawDie
    var rotation: Double = 0
    var result: [Int] = []
    var displayState: Int = 0
}
