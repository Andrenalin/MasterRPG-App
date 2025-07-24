// @copyright André Trettin

import SwiftData
import Foundation

@Model
final class LinkDataModel: Identifiable {
    var id: UUID
    var itemId: UUID
    var entryId: UUID?
    var module: NetworkModules
    var name: AttributedString {
        get {
            nameModel.value
        }
        set {
            nameModel.value = newValue
        }
    }

    @Relationship(deleteRule: .cascade)
    private var nameModel: AttributedStringModel

    init(name: AttributedString, itemId: UUID, entryId: UUID? = nil, module: NetworkModules) {
        self.id = UUID()
        self.itemId = itemId
        self.entryId = entryId
        self.module = module
        self.nameModel = AttributedStringModel(value: name, scope: .link)
    }
}
