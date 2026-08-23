// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG

// Renamed from GameController+MapSync.swift — "Map" was redundant inside
// MapRPG's own GameController. `saveAll()` moved to +Metadata.swift
// (export/persistence, not sync) and `demoNextMap` moved to +Demo.swift.
// See CODE_AUDIT_Game §9.25.

extension GameController {
    @MainActor
    @discardableResult
    func updateMap(for itemId: UUID, with data: NetworkCodableDataType) -> Bool {
        guard let mapData = data.data else { return false }
        let text = String(decoding: mapData, as: UTF8.self)
        guard updateMap(for: itemId, with: text) else { return false }
        mapGameModel.recordAuthoritativeGeneration(data)
        return true
    }

    @MainActor
    func mapUpdateResult(for itemId: UUID) -> String {
        let model = gameItem(for: itemId)
        let first = model.entries.reduce("") { $0 + "\($1.id):\($1.isShown):\($1.focused)|" }
        return first + (JSONString.encode(value: [model.pointer] + model.mapPins) ?? "")
    }

    @MainActor
    func networkMapUpdate(for itemId: UUID) -> NetworkCodableDataType {
        // See CODE_AUDIT §9.2 — shared envelope factory.
        Self.mapNetworkData(
            id: itemId,
            generation: networkGeneration(for: itemId),
            data: Data(mapUpdateResult(for: itemId).utf8)
        )
    }

    @MainActor
    func networkPin(itemId: UUID, position: MapPinModel) -> NetworkCodableDataType {
        Self.mapNetworkData(
            id: itemId,
            generation: networkGeneration(for: itemId),
            data: position.encodeData()
        )
    }
}
