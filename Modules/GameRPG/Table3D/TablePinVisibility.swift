// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import Foundation
import MapRPG

/// Which pins the table shows to whom. Pure, so the rule is testable without RealityKit.
/// See CODE_AUDIT_26 §10.3.
@MainActor
enum TablePinVisibility {
    /// The pins of `mapModel` plus its pointer when the pointer is on show. The pins are placed as
    /// the 2D map shows them: one without a location stands in the map's first entry.
    static func allPins(of mapModel: MapModel?) -> [MapPinModel] {
        guard let mapModel else { return [] }
        let pointerPins = mapModel.pointer.isShown ? [mapModel.pointer] : []
        return MapPinPlacement.displayPins(mapModel.mapPins, in: mapModel, pinScale: mapModel.pinScale) + pointerPins
    }

    /// The master sees every pin (hidden ones dimmed); players see a pin when it is shown and,
    /// for monsters, not covered by fog. A pin id listed twice is shown once.
    static func visiblePins(allPins: [MapPinModel], mapModel: MapModel?, isGameMaster: Bool) -> [MapPinModel] {
        var seenPinIds: Set<UUID> = []
        return allPins.filter { seenPinIds.insert($0.id).inserted }.filter { pin in
            if isGameMaster { return true }
            guard pin.isShown else { return false }
            if pin.id == mapModel?.pointer.id { return true }
            if pin.isPlayer { return true }
            return mapModel.map { !$0.isLocationHiddenForPlayers(pin.location) } ?? true
        }
    }
}
#endif
