// @copyright André Trettin

import CoreRPG
//import CodableModel
import Foundation
import SwiftData

@Model 
public final class MapDataModel {
    public init(itemId: UUID = UUID(), photoId: UUID? = nil, width: CGFloat = 1200, height: CGFloat = 800, entries: [MapEntryDataModel] = [], pinScale: CGFloat = 1.0, hexMapScale: Double = 0, scale: CGFloat = 1.0) {
        self.itemId = itemId
        self.photoId = photoId
        self.width = width
        self.height = height
        self.pinScale = pinScale
        self.hexMapScale = hexMapScale
        self.scale = scale
    }
    
    var itemId: UUID = UUID()
    var photoId: UUID? = nil
    var width: CGFloat = 1200
    var height: CGFloat = 800
    
    @Relationship(deleteRule: .cascade) private var entries_: [MapEntryDataModel]? = []
    //var displayConfig:
    
    var pinScale: CGFloat = 1.0
    var hexMapScale: Double = 0

    @Transient
    var scale: CGFloat = 1.0
    
    // MARK: Codable
    
    struct MapDataModelCodable: Equatable, Hashable, Codable, Sendable {
        init(itemId: UUID = UUID(), photoId: UUID? = nil, width: CGFloat = 1200, height: CGFloat = 800, entries: [MapEntryDataModel.MapEntryDataModelCodable] = [], pinScale: CGFloat = 1.0, hexMapScale: Double = 0, scale: CGFloat = 1.0, links: [LinkDataModel.LinkDataModelCodable] = []) {
            self.itemId = itemId
            self.photoId = photoId
            self.width = width
            self.height = height
            self.entries = entries
            self.pinScale = pinScale
            self.hexMapScale = hexMapScale
            self.scale = scale
            self.links = links
        }
        var itemId: UUID = UUID()
        var photoId: UUID? = nil
        var width: CGFloat = 1200
        var height: CGFloat = 800
        var entries: [MapEntryDataModel.MapEntryDataModelCodable] = []
        var pinScale: CGFloat = 1.0
        var hexMapScale: Double = 0
        var scale: CGFloat = 1.0
        var links: [LinkDataModel.LinkDataModelCodable] = []
    }
    
    convenience init(_ model: MapDataModelCodable) {
        self.init(itemId: model.itemId, photoId: model.photoId, width: model.width, height: model.height, entries: [], pinScale: model.pinScale, hexMapScale: model.hexMapScale, scale: model.scale)
        self.entries = model.entries.map { MapEntryDataModel($0) }
    }
    
    @MainActor
    var codableModel: MapDataModelCodable {
        MapDataModelCodable(
            itemId: itemId,
            photoId: photoId,
            width: width,
            height: height,
            entries: entries.map {
                $0.codableModel
            },
            pinScale: pinScale,
            hexMapScale: hexMapScale,
            scale: scale,
            links: entries.flatMap {
                $0.links
            }
        )
    }
    
    func replace(_ model: MapDataModelCodable) {
        itemId = model.itemId
        photoId = model.photoId
        width = model.width
        height = model.height
        entries = model.entries.map { MapEntryDataModel($0) }
        pinScale = model.pinScale
        hexMapScale = model.hexMapScale
        scale = model.scale
    }
}

extension MapDataModel {
    var entries: [MapEntryDataModel] {
        get {
            guard let all = entries_ else { return [] }
            return all.sorted { $0.index < $1.index }
        }
        set {
            entries_ = newValue
        }
    }
}
