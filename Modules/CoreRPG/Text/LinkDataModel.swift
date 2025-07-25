// @copyright André Trettin

import SwiftData
import Foundation

@Model
final class LinkDataModel: Identifiable {
    var id: UUID
    // source
    var sourceId: UUID
    var sourceEntryId: UUID?
    var sourceModule: NetworkModules
    // destination
    var destinationId: UUID
    var destinationEntryId: UUID?
    var destinationModule: NetworkModules

    var name: AttributedString {
        get { nameModel.value }
        set { nameModel.value = newValue }
    }

    @Relationship(deleteRule: .cascade)
    private var nameModel: AttributedStringModel

    init(name: AttributedString, sourceId: UUID, sourceEntryId: UUID? = nil, sourceModule: NetworkModules, destinationId: UUID, destinationEntryId: UUID?, destinationModel: NetworkModules) {
        self.id = UUID()
        self.sourceId = sourceId
        self.sourceEntryId = sourceEntryId
        self.sourceModule = sourceModule
        self.destinationId = destinationId
        self.destinationEntryId = destinationEntryId
        self.destinationModule = destinationModel
        self.nameModel = AttributedStringModel(value: name, scope: .link)
    }
}
