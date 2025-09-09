// @copyright André Trettin

import SwiftData
import Foundation

@Model
public final class LinkDataModel: Identifiable {
    public init(name: String, sourceId: UUID, sourceEntryId: UUID? = nil, sourceModule: NetworkModules, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModel: NetworkModules) {
        self.id = UUID()
        self.name = name
        self.sourceId = sourceId
        self.sourceEntryId = sourceEntryId
        self.sourceModule = sourceModule
        self.destinationId = destinationId
        self.destinationEntryId = destinationEntryId
        self.destinationModule = destinationModel
    }

    public var id: UUID = UUID()

    var name: String = ""
    // source
    var sourceId: UUID = UUID()
    var sourceEntryId: UUID? = nil
    var sourceModule: NetworkModules = NetworkModules.none
    // destination
    var destinationId: UUID = UUID()
    var destinationEntryId: UUID? = nil
    var destinationModule: NetworkModules = NetworkModules.none
}
