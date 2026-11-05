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
import DiceRPG
import TabletopKit
#endif

extension GameTableModel {
    // MARK: - Pin Selection & Gestures

    func updateSelectedPinState(mapModel: MapModel?) {
        guard isGameMaster,
              let selectedPinId,
              let pin = mapModel?.mapPins.first(where: { $0.id == selectedPinId }),
              setup.pinPawns.contains(where: { $0.pinId == selectedPinId }) else {
            clearPinSelection()
            return
        }
        selectedPin = pin
        updatePinMenuAttachmentPosition()
    }

    func clearPinSelection() {
        selectedPinId = nil
        selectedPin = nil
        pinMenuPopover.hide()
    }

    func updatePinMenuAttachmentPosition(cachedPawn: PinPawn? = nil) {
        guard isGameMaster,
              selectedPin != nil,
              let selectedPinId,
              let pawn = cachedPawn ?? setup.pinPawns.first(where: { $0.pinId == selectedPinId }) else {
            pinMenuPopover.hide()
            return
        }
        let pinPosition = pawn.entity.position
        pinMenuPopover.show(at: SIMD3<Float>(
            pinPosition.x,
            pinPosition.y + Self.pinMenuArrowTipHeight,
            pinPosition.z
        ))
    }

    /// How far above a pin's base the popover's arrow ends: just clear of the token's top.
    static let pinMenuArrowTipHeight: Float = 0.03

#if !os(visionOS)
    /// Projects the selected pin into the table view for the pin action popover. Runs every
    /// rendered frame; `project` maps a scene position to the table view's coordinate space.
    func updatePinMenuSource(project: (SIMD3<Float>) -> CGPoint?) {
        guard isGameMaster,
              selectedPin != nil,
              let selectedPinId,
              let pawn = setup.pinPawns.first(where: { $0.pinId == selectedPinId }) else {
            if pinMenuSource != nil {
                pinMenuSource = nil
            }
            return
        }
        let bounds = pawn.entity.visualBounds(relativeTo: nil)
        let corners = TablePinMenuSource.corners(min: bounds.min, max: bounds.max)
        let source = TablePinMenuSource.frame(enclosing: corners.map(project)).map {
            TablePinMenuSource(pinId: selectedPinId, frame: $0)
        }
        guard let source else {
            if pinMenuSource != nil {
                pinMenuSource = nil
            }
            return
        }
        if source.differsVisibly(from: pinMenuSource) {
            pinMenuSource = source
        }
    }
#endif

    /// Pin drag: follow the finger on the board plane. Runs on every `.onChanged` delta —
    /// potentially dozens of times per second during one drag — so the resolved pawn is
    /// cached across calls instead of re-scanning `pinPawns` (and, when the dragged pin is
    /// also the selected one, a second scan inside `updatePinMenuAttachmentPosition`) on every
    /// tick.
    func pinDragChanged(pinId: UUID, position: SIMD3<Float>) {
        guard canMovePin(pinId) else { return }
        let pawn: PinPawn
        if let cachedDragPawn, cachedDragPawn.pinId == pinId {
            pawn = cachedDragPawn.pawn
        } else {
            guard let found = setup.pinPawns.first(where: { $0.pinId == pinId }) else { return }
            pawn = found
            cachedDragPawn = (pinId, found)
        }
        pawn.entity.position = SIMD3<Float>(position.x, MapTableProjection.pinHeight, position.z)
        if selectedPinId == pinId {
            updatePinMenuAttachmentPosition(cachedPawn: pawn)
        }
    }

    /// Pin drop: write the move back into the map model, then network it. The pawns are always
    /// resynced afterwards, so a rejected or impossible drop snaps the token back to the model's
    /// location instead of leaving it where it was released.
    func pinDragEnded(pinId: UUID, position: SIMD3<Float>) {
        cachedDragPawn = nil
        defer { syncPawnsWithMapPins() }
        guard canMovePin(pinId), let mapId = currentMapId,
              let mapImage = currentMapImage,
              let mapModel = currentMapModel(),
              let coordinateSize = MapTableProjection.canvasSize(
                  map: mapModel,
                  image: mapImage,
                  degrees: currentMapDegrees
              ) else { return }
        let projection = MapTableProjection(
            imageSize: coordinateSize,
            planeAspectRatio: MapTableProjection.planeAspectRatio(
                photoSize: mapImage.size,
                degrees: currentMapDegrees,
                canvasSize: coordinateSize
            )
        )
        let location = projection.mapLocation(
            for: SIMD3<Float>(position.x, MapTableProjection.pinHeight, position.z)
        )

        if pinId == mapModel.pointer.id {
            guard mapRoot.mapGameControllable.movePointer(itemId: mapId, location: location) else { return }
            if isGameMaster {
                broadcastMapEdit(for: mapId)
            } else {
                sendPlayerPointerUpdate(mapId: mapId)
            }
            return
        }

        guard mapRoot.mapGameControllable.movePin(
            itemId: mapId,
            pinId: pinId,
            location: location
        ) else { return }
        if isGameMaster {
            broadcastMapEdit(for: mapId)
        } else {
            sendPlayerPinUpdate(mapId: mapId, pinId: pinId)
        }
    }

    /// A tap first adds a missing combatant while Surprise is being
    /// prepared. Otherwise a player's tap toggles the shared highlight,
    /// while a master's tap instead opens/closes the local pin action
    /// menu — presentation-only state, so it neither highlights nor
    /// broadcasts. Long press is no longer used for pins.
    func pinTapped(pinId: UUID) {
        guard let mapId = currentMapId,
              let mapModel = currentMapModel(),
              pinId != mapModel.pointer.id,
              setup.pinPawns.contains(where: { $0.pinId == pinId }) else { return }
        if addPinToBattleRound(pinId: pinId) {
            return
        }
        if isGameMaster {
            toggleSelectedPin(pinId: pinId, mapModel: mapModel)
            return
        }
        guard mapRoot.mapGameControllable.toggleHighlightPin(itemId: mapId, pinId: pinId, isGameMaster: isGameMaster) else { return }
        syncPawnsWithMapPins()
        sendPlayerPinUpdate(mapId: mapId, pinId: pinId)
    }

    /// Opens or closes the master's local pin action menu — presentation-only
    /// state, so it bypasses map mutation/broadcast entirely.
    private func toggleSelectedPin(pinId: UUID, mapModel: MapModel) {
        if selectedPinId == pinId {
            clearPinSelection()
        } else {
            // The menu and the pin's photo popover would cover each other.
            if photoPinId == pinId { clearPinPhoto() }
            selectedPinId = pinId
            updateSelectedPinState(mapModel: mapModel)
        }
    }

    /// Performs an action of the game master's pin action popover on the selected pin.
    func performSelectedPinAction(_ action: MapPinButtonType) {
        switch action {
        case .dead: toggleSelectedPinDead()
        case .visibility: toggleSelectedPinVisibility()
        case .resize: resizeSelectedPin()
        case .highlight: toggleSelectedPinHighlight()
        case .battle: addSelectedPinToBattleRound()
        case .remove, .copy, .photo, .character:
            // Map editor actions; the game master's popover doesn't offer them.
            break
        }
    }

    func toggleSelectedPinDead() {
        guard isGameMaster, let mapId = currentMapId, let selectedPinId,
              mapRoot.mapGameControllable.toggleDeadPin(itemId: mapId, pinId: selectedPinId) else { return }
        syncPawnsWithMapPins()
        broadcastMapEdit(for: mapId)
    }

    var canAddSelectedPinToBattleRound: Bool {
        guard isGameMaster,
              let selectedPinId else {
            return false
        }
        // Any round of the running battle; a pin that was highlighted first is on the roster as
        // a target without a turn and can still be added.
        return mapRoot.mapGameControllable.battleRoundModel.canJoinBattle(pinId: selectedPinId, on: currentMapId)
    }

    func addSelectedPinToBattleRound() {
        guard let selectedPinId else { return }
        _ = addPinToBattleRound(pinId: selectedPinId, inAnyRound: true)
    }

    func toggleSelectedPinVisibility() {
        guard isGameMaster, let mapId = currentMapId, let selectedPinId,
              mapRoot.mapGameControllable.togglePin(itemId: mapId, pinId: selectedPinId) else { return }
        syncPawnsWithMapPins()
        broadcastMapEdit(for: mapId)
    }

    /// Highlights (red border) the selected pin — the master's local pin
    /// action menu equivalent of a player's single tap, which now opens
    /// this menu instead. See `pinTapped(pinId:)`'s own doc.
    func toggleSelectedPinHighlight() {
        guard isGameMaster, let mapId = currentMapId, let selectedPinId,
              mapRoot.mapGameControllable.toggleHighlightPin(itemId: mapId, pinId: selectedPinId, isGameMaster: isGameMaster) else { return }
        syncPawnsWithMapPins()
        broadcastMapEdit(for: mapId)
    }

    func resizeSelectedPin() {
        guard isGameMaster, let mapId = currentMapId, let selectedPinId,
              mapRoot.mapGameControllable.resizePin(itemId: mapId, pinId: selectedPinId) else { return }
        syncPawnsWithMapPins()
        broadcastMapEdit(for: mapId)
    }

    @discardableResult
    private func addPinToBattleRound(pinId: UUID, inAnyRound: Bool = false) -> Bool {
        guard isGameMaster,
              let mapId = currentMapId else { return false }
        // A tap adds only while the surprise round is prepared; the menu action in any round.
        let added = inAnyRound
            ? mapRoot.mapGameControllable.joinBattle(itemId: mapId, pinId: pinId)
            : mapRoot.mapGameControllable.addBattleCombatant(itemId: mapId, pinId: pinId)
        guard added else { return false }
        syncPawnsWithMapPins()
        broadcastMapEdit(for: mapId)
        broadcastBattleRoundState(for: mapId)
        return true
    }
}

#endif
