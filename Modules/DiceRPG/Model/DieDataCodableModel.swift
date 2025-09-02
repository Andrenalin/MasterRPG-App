// @copyright André Trettin

import Foundation
import SwiftUI

struct DieDataCodableModel: Equatable, Hashable, Codable, Sendable {
    init(id: UUID, index: Int = 0, die: RawDie = .twenty, color: String = "", rotation: Double = 0, result: [Int] = []) {
        self.id = id
        self.index = index
        self.die = die
        self.color = color
        self.rotation = rotation
        self.result = result
    }

    var id: UUID = UUID()
    var index: Int = 0
    var die: RawDie = RawDie.twenty
    var color: String

    var rotation: Double = 0
    var result: [Int] = []
}
