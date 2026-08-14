// @copyright André Trettin

import CoreRPG
import Foundation
import Observation
import TableRPG
import SwiftUI
import CharacterRPG
import PhotoRPG

extension GameController {
    @MainActor
    @discardableResult
    func updateMap(for itemId: UUID, with data: NetworkCodableDataType) -> Bool {
        guard let mapData = data.data, let text = String(data: mapData, encoding: .utf8) else { return false }
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
        let generation = networkGeneration(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: generation.version,
            data: mapUpdateResult(for: itemId).data(using: .utf8),
            assetVersion: generation.assetVersion,
            contentVersion: generation.contentVersion
        )
    }

    @MainActor
    func networkPin(itemId: UUID, position: MapPinModel) -> NetworkCodableDataType {
        let generation = networkGeneration(for: itemId)
        return NetworkCodableDataType(
            id: itemId,
            type: .map,
            version: generation.version,
            data: position.encodeData(),
            assetVersion: generation.assetVersion,
            contentVersion: generation.contentVersion
        )
    }
    
    @MainActor
    func saveAll() -> ItemModuleIds {
        for itemId in gameModel.items {
            gameItem(for: itemId).mapPins = gameItem(for: itemId).mapPins.filter { !$0.isPlayer }
        }
        return exportController.exportingAll()
    }
    
    @MainActor
    func demoNextMap(itemId: UUID, restart: Bool) -> NetworkCodableDataType? {
        let item = gameItem(for: itemId)
        if restart {
            item.entries.forEach {
                item.toggle($0.id)
            }
            return networkMapUpdate(for: itemId)
        }
        guard let firstEntry = item.entries.first(where: { !$0.isShown }) else { return nil }
        item.toggle(firstEntry.id)
        return networkMapUpdate(for: itemId)
    }
}
