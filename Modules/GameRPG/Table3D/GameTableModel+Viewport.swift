// @copyright André Trettin

#if os(iOS) || os(macOS) || os(visionOS)
import CoreRPG
import Foundation
import MapRPG
import PhotoRPG
import RealityKit
import SwiftUI
import os.log

#if os(visionOS)
import Combine
import DiceRPG
import TabletopKit
#endif

extension GameTableModel {
    // MARK: - Viewport & Board Projection

    /// The rect (in the given map's oriented coordinate space, same units as
    /// `MapEntryModel.coordinates`) the 3D board shows — always the full map.
    /// Unlike the 2D map's own room-focus zoom (`MapEditorSession.focus(on:)`),
    /// the 3D board deliberately never crops/zooms into a focused room: its
    /// fixed-size surface makes a fill-and-clip crop feel disorienting in a
    /// way the 2D map's scrollable canvas doesn't. A focused room instead gets
    /// a red highlight border at full scale (see `Board.generateCompositeTexture`
    /// / `GameTableTextureRenderer.render`'s `drawFog`). Kept as the shared
    /// choke point both `GameSetup` implementations (visionOS and iOS/macOS)
    /// route pin positions, room hit-testing, and board-texture framing
    /// through, so "never crop" only has to be decided in one place.
    static func boardFocusRect(entries _: [MapEntryModel], imageSize: CGSize, panOffset _: CGPoint = .zero) -> CGRect {
        CGRect(origin: .zero, size: imageSize)
    }

    var rooms: [MapEntryModel] {
        currentMapModel()?.entries ?? []
    }

    /// The room the game master currently has focused, mirroring the 2D
    /// map's own notion of a focus room (which is the only one that actually
    /// zooms into it — see `boardFocusRect`). Used by the shared
    /// `ChooseMapPinsButton` toolbar control to know where a newly added
    /// monster pin should land.
    var focusedRoomId: UUID? {
        rooms.first(where: \.focused)?.id
    }

    func resetViewportPanIfFocusedRoomChanged(entries: [MapEntryModel]) {
        let currentFocusedRoomId = entries.first(where: \.focused)?.id
        guard currentFocusedRoomId != lastFocusedRoomId else { return }
        lastFocusedRoomId = currentFocusedRoomId
        manualViewportOffset = .zero
    }

    /// Updates `manualViewportOffset` by a map-coordinate delta — dragging
    /// the map surface while a room is focused. No longer has any rendering
    /// effect (`boardFocusRect` never crops), since only the 2D map still
    /// zooms into a focused room; kept, along with the gesture that drives
    /// it, rather than ripping the pan gesture out entirely. No longer
    /// triggers a fog/board recomposite either, for the same reason — see
    /// `renderSignature`'s doc comment. See CODE_AUDIT_10 §7.1.
    private func panViewport(by delta: CGPoint) {
        guard focusedRoomId != nil else { return }
        // Dragging right should bring content on the left into view (like
        // dragging a photo, not scrolling a window onto it) — the visible
        // crop moves opposite the finger.
        manualViewportOffset.x -= delta.x
        manualViewportOffset.y -= delta.y
        syncPawnsWithMapPins()
    }

    /// Entry point for `GameTableView.viewportPanGesture`: converts a drag's
    /// start/end table positions into a map-coordinate delta using whatever
    /// projection is currently on screen, then pans by it. No-ops without a
    /// focused room. See `panViewport(by:)` — this has no visible effect on
    /// the 3D board any more, since it never crops into a focused room.
    func panViewport(fromTableStart start: SIMD3<Float>, toTableEnd end: SIMD3<Float>, expectedRoomId: UUID?) {
        // Discards the commit if the focused room changed mid-gesture — e.g. a network-driven
        // focus change from the GM's own device while this player was mid-drag. Applying the
        // delta against a since-changed baseline would otherwise produce a visible,
        // nonsensical jump instead of just dropping the now-meaningless drag. See CODE_AUDIT §5.12.
        guard let expectedRoomId, focusedRoomId == expectedRoomId,
              let mapModel = currentMapModel() else { return }
        // Falls back to the rendered image's own size when the map has no explicit
        // width/height, matching `pinDragEnded`'s fallback — without it, panning was a silent
        // no-op on such maps (pin-dropping still worked) while every other coordinate path
        // already handled this case. See CODE_AUDIT §5.11.
        let coordinateSize: CGSize
        if mapModel.width > 0, mapModel.height > 0 {
            coordinateSize = CGSize(width: mapModel.width, height: mapModel.height)
        } else if let mapImage = currentMapImage {
            coordinateSize = MapTableProjection.orientedImageSize(
                mapImage.fixedSize,
                degrees: currentMapDegrees
            )
        } else {
            return
        }
        let projection = MapTableProjection(
            imageSize: coordinateSize,
            degrees: 0,
            focusRect: Self.boardFocusRect(
                entries: mapModel.entries,
                imageSize: coordinateSize,
                panOffset: manualViewportOffset
            )
        )
        let startLocation = projection.mapLocation(for: start)
        let endLocation = projection.mapLocation(for: end)
        panViewport(by: CGPoint(x: endLocation.x - startLocation.x, y: endLocation.y - startLocation.y))
    }

    /// Re-syncs pawns and re-broadcasts after a map mutation made outside this
    /// model — e.g. `ChooseMapPinsButton` adding monster pins directly through
    /// `EditController`, bypassing this model's own mutation methods (which
    /// all sync/broadcast themselves). Local sync always runs so the game
    /// master sees the change immediately; broadcasting respects `isStreaming`
    /// the same way the 2D toolbar's "Share Map" toggle does.
    func syncAfterExternalEdit() {
        syncPawnsWithMapPins()
        guard isStreaming, isGameMaster, let mapId = currentMapId else { return }
        broadcastMapState(for: mapId)
    }

    var pointer: MapPinModel? {
        currentMapModel()?.pointer
    }
}

#endif
