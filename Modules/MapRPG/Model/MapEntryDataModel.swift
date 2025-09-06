// @copyright André Trettin

import CodableModel
import Foundation
import SwiftData

@Model @CodableModel
public final class MapEntryDataModel {
    public init(itemId: UUID = UUID(), entryId: UUID = UUID(), index: Int = 0, name: String = "", content: String = "", coordinates: [CGPoint] = [], isHexGrid: Bool = false, isShown: Bool = false, focused: Bool = false, parent: MapDataModel? = nil) {
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
    
    var itemId: UUID = UUID()
    var entryId: UUID = UUID()
    var index: Int = 0
    
    var name: String = ""
    var content: String = ""
    
    var coordinates: [CGPoint] = []
    
    var isHexGrid: Bool = false
    var isShown: Bool = false
    var focused: Bool = false

    @CodableIgnored
    var parent: MapDataModel? = nil
}
