// @copyright André Trettin

import CoreRPG
import SwiftUI

// Split out of MapEditorCanvas.swift — see CODE_AUDIT §9.13.

/// Image and the invisible interaction surface — vector/texture content that
/// scales cleanly through an ancestor `.scaleEffect`, unlike the room/fog
/// Canvas layers (see `MapRoomOverlayCanvas`).
struct MapLogicalCanvasBaseLayer: View {
    let session: MapEditorSession
    let image: AKImage
    let degrees: Double
    let interactionTransform: GestureState<ViewportTransform?>

    private var canvasSize: CGSize { session.mapCanvasSize }

    var body: some View {
        ZStack(alignment: .topLeading) {
            MapOrientedImage(image: image, degrees: degrees, canvasSize: canvasSize)
                .allowsHitTesting(false)

            // Keep an interaction surface in the logical canvas as well as
            // behind it. Passive drawing layers deliberately do not receive
            // hits, but their full-size containers can otherwise prevent a
            // pinch from reaching the background plane on editor surfaces.
            // Pins, room hit targets, and needles are rendered above this
            // plane and retain their higher-priority gestures.
            MapViewportInteractionPlane(
                session: session,
                interactionTransform: interactionTransform,
                surface: .content(canvasSize)
            )
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

/// Room hit targets and ordinary pins — sits below the fog-of-war overlay so
/// fog can hide an ordinary pin whose room is unrevealed.
struct MapLogicalCanvasHitAndOrdinaryPins: View {
    let session: MapEditorSession
    let viewportScale: CGFloat
    /// See `MapRoomHitLayer.hitCullingRect`.
    var roomHitCullingRect: CGRect = .infinite
    let interactionTransform: GestureState<ViewportTransform?>

    private var canvasSize: CGSize { session.mapCanvasSize }
    private var activeEntryId: UUID? { session.editEntries.entries.first?.id }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !session.configuration.isTileEditor {
                MapRoomHitLayer(
                    rooms: session.entries,
                    session: session,
                    isEnabled: session.roomHitTargetsAreEnabled,
                    excludingEntryId: activeEntryId,
                    visibleContentRect: roomHitCullingRect,
                    interactionTransform: interactionTransform
                )

                MapPinLayer(
                    pins: session.pins,
                    kind: .ordinary,
                    displayMode: session.displayMode,
                    mapMode: session.mapMode,
                    playerPinId: session.playerPinId,
                    pinScale: session.pinScale,
                    viewportScale: viewportScale
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

/// The pointer and the pins whose photo is shared — sit above the fog-of-war overlay so they
/// stay visible even in an unrevealed room.
struct MapLogicalCanvasPointerAndPhotoSharedPins: View {
    let session: MapEditorSession
    let viewportScale: CGFloat

    private var canvasSize: CGSize { session.mapCanvasSize }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if !session.configuration.isTileEditor {
                MapPinLayer(
                    pins: session.pins,
                    kind: .pointer,
                    displayMode: session.displayMode,
                    mapMode: session.mapMode,
                    playerPinId: session.playerPinId,
                    pinScale: session.pinScale,
                    viewportScale: viewportScale
                )

                MapPinLayer(
                    pins: session.pins,
                    kind: .photoShared,
                    displayMode: session.displayMode,
                    mapMode: session.mapMode,
                    playerPinId: session.playerPinId,
                    pinScale: session.pinScale,
                    viewportScale: viewportScale
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

/// The selected room's needle-editing handles (edit mode only).
struct MapLogicalCanvasNeedleLayer: View {
    let session: MapEditorSession
    let viewportScale: CGFloat

    private var canvasSize: CGSize { session.mapCanvasSize }
    private var activeEntryId: UUID? { session.editEntries.entries.first?.id }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if session.mapMode == .edit,
               session.displayMode == .master || session.displayMode == .reader,
               let entryId = activeEntryId {
                MapNeedleLayer(
                    entries: session.editEntries,
                    entryId: entryId,
                    session: session,
                    viewportScale: viewportScale
                )
            }
        }
        .frame(width: canvasSize.width, height: canvasSize.height, alignment: .topLeading)
    }
}

/// The GM boundary/dim overlay (`.base`) or the player's fog-of-war
/// (`.fog`). Unlike the layers above, this renders in viewport space and
/// applies pan/zoom inside its own `GraphicsContext` — see
/// `MapPassiveRoomCanvas`'s `viewportSize` doc comment for why that matters
/// for a large map fitted far below its native scale.
struct MapRoomOverlayCanvas: View {
    let session: MapEditorSession
    let map: MapModel
    let image: AKImage
    let degrees: Double
    let phase: MapRoomCanvasPhase
    let transform: ViewportTransform
    let viewportSize: CGSize

    private var canvasSize: CGSize { session.mapCanvasSize }
    private var activeEntryId: UUID? { session.editEntries.entries.first?.id }
    private var displayConfig: DisplayConfigModel {
        session.workingCopy?.displayConfig ?? map.displayConfig
    }

    var body: some View {
        if !session.configuration.isTileEditor {
            MapPassiveRoomCanvas(
                rooms: session.entries,
                displayMode: session.displayMode,
                displayConfig: displayConfig,
                phase: phase,
                mapImage: image,
                degrees: degrees,
                canvasSize: canvasSize,
                transform: transform,
                viewportSize: viewportSize,
                excludingEntryId: activeEntryId
            )
        }
    }
}

/// The currently-edited room's own boundary/fog preview (edit mode only),
/// in the same viewport-space style as `MapRoomOverlayCanvas`.
struct MapActiveRoomOverlayCanvas: View {
    let session: MapEditorSession
    let map: MapModel
    let image: AKImage
    let degrees: Double
    let transform: ViewportTransform
    let viewportSize: CGSize

    private var canvasSize: CGSize { session.mapCanvasSize }
    private var displayConfig: DisplayConfigModel {
        session.workingCopy?.displayConfig ?? map.displayConfig
    }

    var body: some View {
        if session.mapMode == .edit {
            MapActiveRoomLayer(
                rooms: session.editEntries,
                displayMode: session.displayMode,
                displayConfig: displayConfig,
                mapImage: image,
                degrees: degrees,
                canvasSize: canvasSize,
                transform: transform,
                viewportSize: viewportSize
            )
        }
    }
}
