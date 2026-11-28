// @copyright André Trettin

import CoreRPG
import Foundation

extension MapModel {
    /// Undo and redo of a map edit revert the map's content too: rooms go through the shared
    /// entry merge, everything else here. A forced save during a game never applies these
    /// (`hasSessionOnlyEntries`, no `applyModuleEdit`). See CODE_AUDIT_Edit_Save §5.2, §5.13.
    public func applyModuleUndo(from base: MapModel, to edited: MapModel) {
        if base.displayConfig != edited.displayConfig { displayConfig = edited.displayConfig }
        if base.photoId != edited.photoId { photoId = edited.photoId }
        if base.width != edited.width { width = edited.width }
        if base.height != edited.height { height = edited.height }
        if base.mapPins != edited.mapPins { mapPins = edited.mapPins }
        if base.walls != edited.walls { walls = edited.walls }
        if base.pinScale != edited.pinScale { pinScale = edited.pinScale }
        if base.hexMapScale != edited.hexMapScale { hexMapScale = edited.hexMapScale }
        if base.degrees != edited.degrees { degrees = edited.degrees }
        if base.hasRecordedDegrees != edited.hasRecordedDegrees { hasRecordedDegrees = edited.hasRecordedDegrees }
    }
}

extension MapEntryModel {
    /// Field by field (used by undo; a forced save never applies map rooms): undoing a room's
    /// text keeps the reveal state another edit set meanwhile. See CODE_AUDIT_Edit_Save §5.11.
    public mutating func applyEdit(from base: MapEntryModel, to edited: MapEntryModel) {
        if base.name != edited.name { name = edited.name }
        if base.content != edited.content { content = edited.content }
        if base.coordinates != edited.coordinates { coordinates = edited.coordinates }
        if base.isShown != edited.isShown { isShown = edited.isShown }
        if base.focused != edited.focused { focused = edited.focused }
        if base.isHexGrid != edited.isHexGrid { isHexGrid = edited.isHexGrid }
        if base.displayState != edited.displayState { displayState = edited.displayState }
    }
}
