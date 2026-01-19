// @copyright André Trettin

import SwiftData
import Foundation

@Model public final class LinkDataModel {
    public init(id: UUID = UUID()) {
        self.id = id
    }
    public var id: UUID = UUID()
}
