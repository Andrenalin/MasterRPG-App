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
        // `reduce(into:)` appends in place; `reduce("")` copied the whole string per entry
        // (quadratic on hex maps). See CODE_AUDIT_17 §7.3.
        let first = model.entries.reduce(into: "") { $0 += "\($1.id):\($1.isShown):\($1.focused)|" }
        return first + (JSONString.encode(value: [Self.pointerVisibleToPlayers(in: model)] + Self.pinsVisibleToPlayers(in: model)) ?? "")
    }

    /// The pins a `.mapState` message may carry. The message only ever goes master to players, so
    /// a hidden pin is left out entirely: its name, portrait id, character link and position are
    /// not on a player device until the pin is shown. A player replaces its pins with this list, so
    /// a pin the game master hides disappears there. A monster inside an unrevealed room counts as
    /// hidden too, so it goes out when that room is revealed. See CODE_AUDIT_22 §6.1,
    /// CODE_AUDIT_23 §6.1.
    @MainActor
    static func pinsVisibleToPlayers(in model: MapModel) -> [MapPinModel] {
        model.mapPins.filter { model.isPinVisibleToPlayers($0) }
    }

    /// The shared pointer as players may read it: a hidden pointer keeps no position, so players do
    /// not learn where the game master is pointing before it is shown. See CODE_AUDIT_23 §6.2.
    @MainActor
    static func pointerVisibleToPlayers(in model: MapModel) -> MapPinModel {
        guard !model.pointer.isShown else { return model.pointer }
        var pointer = model.pointer
        pointer.location = .zero
        return pointer
    }

    /// The same live state as comparable values, for a sender that wants to
    /// know whether a map state message would say anything new. The message
    /// itself cannot be compared: its JSON has no fixed key order, so two
    /// encodings of one state differ byte for byte. Must cover exactly what
    /// `mapUpdateResult(for:)` and the envelope of `networkMapUpdate(for:)`
    /// carry.
    @MainActor
    func mapLiveState(for itemId: UUID) -> MapLiveState {
        let model = gameItem(for: itemId)
        return MapLiveState(
            mapId: itemId,
            generation: networkGeneration(for: itemId),
            rooms: model.entries.map { MapLiveState.Room(id: $0.id, isShown: $0.isShown, focused: $0.focused) },
            pointer: Self.pointerVisibleToPlayers(in: model),
            pins: Self.pinsVisibleToPlayers(in: model)
        )
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

/// What a `.mapState` message carries, as values that can be compared: the
/// map's generation, each room's visibility and focus, the pointer and every
/// pin. See `GameController.mapLiveState(for:)`.
public struct MapLiveState: Equatable, Sendable {
    struct Room: Equatable, Sendable {
        let id: UUID
        let isShown: Bool
        let focused: Bool
    }

    let mapId: UUID
    let generation: MapGameModel.AuthoritativeGeneration
    let rooms: [Room]
    let pointer: MapPinModel
    let pins: [MapPinModel]
}
