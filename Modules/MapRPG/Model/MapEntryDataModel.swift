// @copyright André Trettin

import CoreRPG
import Foundation
import SwiftData

@Model 
public final class MapEntryDataModel {
    public init(
        itemId: UUID = UUID(),
        entryId: UUID = UUID(),
        index: Int = 0,
        name: String = "",
        content: String = "",
        coordinates: [CGPoint] = [],
        isHexGrid: Bool = false,
        isShown: Bool = false,
        focused: Bool = false,
        parent: MapDataModel? = nil
    ) {
        self.itemId = itemId
        self.entryId = entryId
        self.index = index
        self.name = name
        self.content = content
        self.coordinates = coordinates
        self.isHexGrid = isHexGrid
        self.isShown = isShown
        self.focused = focused
        self.parent = parent
    }
    
    public var itemId: UUID = UUID()
    @Attribute(.preserveValueOnDeletion)
    public var entryId: UUID = UUID()
    public var index: Int = 0
    
    public var name: String = ""
    public var content: String = ""
    
    var coordinates: [CGPoint] = []
    
    var isHexGrid: Bool = false
    var isShown: Bool = false
    var focused: Bool = false
    
    //@CodableIgnored
    var parent: MapDataModel? = nil
    
    // MARK: Codable
    
    struct MapEntryDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "", coordinates: [CGPoint] = [], isHexGrid: Bool = false, isShown: Bool = false, focused: Bool = false) {
            self.itemId = itemId
            self.entryId = entryId
            self.index = index
            self.name = name
            self.content = content
            self.coordinates = coordinates
            self.isHexGrid = isHexGrid
            self.isShown = isShown
            self.focused = focused
        }
        var itemId: UUID = UUID()
        var entryId: UUID = UUID()
        var index: Int = 0
        var name: String = ""
        var content: String = ""
        var coordinates: [CGPoint] = []
        var isHexGrid: Bool = false
        var isShown: Bool = false
        var focused: Bool = false
    }
    
    convenience init(_ model: MapEntryDataModelCodable) {
        self.init(itemId: model.itemId, entryId: model.entryId, index: model.index, name: model.name, content: model.content, coordinates: model.coordinates, isHexGrid: model.isHexGrid, isShown: model.isShown, focused: model.focused)
    }
    
    var codableModel: MapEntryDataModelCodable {
        MapEntryDataModelCodable(
            itemId: itemId,
            entryId: entryId,
            index: index,
            name: name,
            content: content,
            coordinates: coordinates,
            isHexGrid: isHexGrid,
            isShown: isShown,
            focused: focused
        )
    }
    
    func replace(_ model: MapEntryDataModelCodable) {
        itemId = model.itemId
        entryId = model.entryId
        index = model.index
        name = model.name
        content = model.content
        coordinates = model.coordinates
        isHexGrid = model.isHexGrid
        isShown = model.isShown
        focused = model.focused
    }
    
    @MainActor
    var links: [LinkDataModel.Value] {
        guard let modelContext else { return [] }
        let linkRegisterController = LinkRegisterController(container: modelContext.container)
        return linkRegisterController.linkDataModel(in: content).map { $0.codableModel }
    }
    
    func duplicate(newItemId: UUID, newEntryId: UUID) -> MapEntryDataModel {
        MapEntryDataModel(
            itemId: newItemId,
            entryId: newEntryId,
            index: index,
            name: name,
            content: content,
            coordinates: coordinates,
            isHexGrid: isHexGrid,
            isShown: isShown,
            focused: focused,
            parent: nil
        )
    }
}

extension MapEntryDataModel: EntryPersistentModel {
    public func duplicate(name: String, index: Int) -> MapEntryDataModel {
        MapEntryDataModel(
            itemId: itemId,
            entryId: UUID(),
            index: index,
            name: name,
            content: content,
            coordinates: coordinates,
            isHexGrid: isHexGrid,
            isShown: isShown,
            focused: focused,
            parent: parent
        )
    }
}

