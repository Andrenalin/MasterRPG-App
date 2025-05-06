// @copyright André Trettin

import AppIntents
import AndrenalinKit

public struct DiceWidgetModel: Sendable {
    public init(itemId: UUID, name: String, displayName: String, root: DiceRoot) {
        self.itemId = itemId
        self.name = name
        self.displayName = displayName
        self.root = root
    }
    
    public let itemId: UUID
    public let name: String
    public let displayName: String
    
    public let root: DiceRoot
    
    @MainActor
    public func link() -> URL {
        URL(string: root.itemController.itemOrEmpty(for: itemId).urlAdr(linkNumber: 0))!
    }
}
