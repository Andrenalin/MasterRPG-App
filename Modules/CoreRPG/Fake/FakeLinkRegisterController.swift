// @copyright André Trettin

import SwiftData
import SwiftUI

@MainActor
public struct FakeLinkRegisterController: LinkRegisterControllable {
    public init() {
        self.model = LinkRegisterListModel()
    }
    
    @MainActor public let model: LinkRegisterListModel
    
    @MainActor public func used(for link: ItemRowModel) -> [EffectedItemModel] {
        [
            EffectedItemModel(id: UUID(), name: "Mega Schrott", module: .table),
            EffectedItemModel(id: UUID(), name: "Beute 5", module: .table),
            EffectedItemModel(id: UUID(), name: "Dice 20", module: .dice)
        ]
    }
    
    @MainActor public func repairLinks(for items: [ItemRowModel]) {}
    
    static let fake = FakeLinkRegisterController()
}

public extension LinkRegisterController {
    static let fake = LinkRegisterController(root: nil)
}
