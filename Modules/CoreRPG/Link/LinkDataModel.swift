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

    public struct LinkDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(name: String, sourceId: UUID, sourceEntryId: UUID? = nil, sourceModule: NetworkModules, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModel: NetworkModules) {
            self.id = UUID()
            self.name = name
            self.sourceId = sourceId
            self.sourceEntryId = sourceEntryId
            self.sourceModule = sourceModule
            self.destinationId = destinationId
            self.destinationEntryId = destinationEntryId
            self.destinationModule = destinationModel
        }

        var id: UUID = UUID()
        var name: String = ""
        var sourceId: UUID = UUID()
        var sourceEntryId: UUID?
        var sourceModule: NetworkModules = .none
        var destinationId: UUID = UUID()
        var destinationEntryId: UUID?
        var destinationModule: NetworkModules = .none
    }

    public convenience init(_ model: LinkDataModelCodable) {
        self.init(
            name: model.name,
            sourceId: model.sourceId,
            sourceEntryId: model.sourceEntryId,
            sourceModule: model.sourceModule,
            destinationId: model.destinationId,
            destinationEntryId: model.destinationEntryId,
            destinationModel: model.destinationModule
        )
    }

    public var codableModel: LinkDataModelCodable {
        LinkDataModelCodable(
            name: name,
            sourceId: sourceId,
            sourceEntryId: sourceEntryId,
            sourceModule: sourceModule,
            destinationId: destinationId,
            destinationEntryId: destinationEntryId,
            destinationModel: destinationModule
        )
    }

    public func replace(_ model: LinkDataModelCodable) {
        name = model.name
        sourceId = model.sourceId
        sourceEntryId = model.sourceEntryId
        sourceModule = model.sourceModule
        destinationId = model.destinationId
        destinationEntryId = model.destinationEntryId
        destinationModule = model.destinationModule
    }
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
