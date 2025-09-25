// @copyright André Trettin

import Foundation

struct PackageMessage: Hashable, Codable, Sendable {
    init(uuid: UUID, count: Int = 1, total: Int = 1, data: Data? = nil) {
        self.uuid = uuid
        self.count = count
        self.total = total
        self.data = data
    }

    let uuid: UUID
    let count: Int
    let total: Int
    let data: Data?
}

