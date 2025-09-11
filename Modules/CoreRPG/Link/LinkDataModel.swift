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

    public internal(set) var id: UUID = UUID()

    public internal(set) var name: String = ""
    // source
    public internal(set) var sourceId: UUID = UUID()
    public internal(set) var sourceEntryId: UUID? = nil
    public internal(set) var sourceModule: NetworkModules = NetworkModules.none
    // destination
    public internal(set) var destinationId: UUID = UUID()
    public internal(set) var destinationEntryId: UUID? = nil
    public internal(set) var destinationModule: NetworkModules = NetworkModules.none
}

public extension LinkDataModel {
    var urlAdr: String {
        "\(URL.appScheme)://\(id)"
    }
    
    var urlName: String {
        name.withoutLink()
    }
    
    var url: String {
        "[\(urlName)](\(urlAdr))"
    }    
}
