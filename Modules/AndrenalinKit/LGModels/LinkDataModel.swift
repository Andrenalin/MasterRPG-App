// @copyright André Trettin

import SwiftData
import Foundation

@Model
public final class LinkDataModel: Identifiable {
    public init(id: UUID = UUID(), name: String, sourceId: UUID, sourceEntryId: UUID? = nil, sourceModule: NetworkModules, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModel: NetworkModules) {
        self.id = id
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
    
    public struct Value: Equatable, Hashable, Codable, Sendable {
        public init(id: UUID, name: String, sourceId: UUID, sourceEntryId: UUID? = nil, sourceModule: NetworkModules, destinationId: UUID, destinationEntryId: UUID? = nil, destinationModel: NetworkModules) {
            self.id = id
            self.name = name
            self.sourceId = sourceId
            self.sourceEntryId = sourceEntryId
            self.sourceModule = sourceModule
            self.destinationId = destinationId
            self.destinationEntryId = destinationEntryId
            self.destinationModule = destinationModel
        }
        
        public var id: UUID = UUID()
        public var name: String = ""
        public var sourceId: UUID = UUID()
        public var sourceEntryId: UUID?
        public var sourceModule: NetworkModules = .none
        public var destinationId: UUID = UUID()
        public var destinationEntryId: UUID?
        public var destinationModule: NetworkModules = .none
    }
    
    public convenience init(_ model: Value) {
        self.init(
            id: model.id,
            name: model.name,
            sourceId: model.sourceId,
            sourceEntryId: model.sourceEntryId,
            sourceModule: model.sourceModule,
            destinationId: model.destinationId,
            destinationEntryId: model.destinationEntryId,
            destinationModel: model.destinationModule
        )
    }
    
    public var codableModel: Value {
        Value(
            id: id,
            name: name,
            sourceId: sourceId,
            sourceEntryId: sourceEntryId,
            sourceModule: sourceModule,
            destinationId: destinationId,
            destinationEntryId: destinationEntryId,
            destinationModel: destinationModule
        )
    }
    
    public func replace(_ model: Value) {
        name = model.name
        sourceId = model.sourceId
        sourceEntryId = model.sourceEntryId
        sourceModule = model.sourceModule
        destinationId = model.destinationId
        destinationEntryId = model.destinationEntryId
        destinationModule = model.destinationModule
    }
    
    public func duplicate() -> LinkDataModel {
        LinkDataModel(
            id: UUID(),
            name: name,
            sourceId: sourceId,
            sourceEntryId: sourceEntryId,
            sourceModule: sourceModule,
            destinationId: destinationId,
            destinationEntryId: destinationEntryId,
            destinationModel: destinationModule
        )
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
