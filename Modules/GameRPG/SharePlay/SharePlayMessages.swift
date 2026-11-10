// @copyright André Trettin

import Foundation

/// One chunk of a Messenger package. `data` is Base64-encoded by `Codable` on top of the package's
/// own JSON encoding: ACCEPTED OVERHEAD, WON'T FIX (CODE_AUDIT_Game_Photo_Audio §7.3). The
/// wire format is proven with SharePlay; see `SharePlaySingleQueuePackageSender`.
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

