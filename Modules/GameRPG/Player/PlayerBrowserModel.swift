// @copyright André Trettin

import Foundation
import Network

struct PlayerBrowserModel: Sendable {
    let name: String
    let endpoint: NWEndpoint
    let interface: NWInterface?
}
