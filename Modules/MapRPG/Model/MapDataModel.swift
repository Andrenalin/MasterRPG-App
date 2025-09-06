// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
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
