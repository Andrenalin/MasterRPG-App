// @copyright André Trettin

import CoreRPG
import SwiftUI

// Split out of MapEditorCanvas.swift — see CODE_AUDIT §9.13.

enum MapPinLayerKind {
    case ordinary
    case pointer
    case zoomed
}

struct MapPinLayer: View {
    let pins: MapPinViewModel
    let kind: MapPinLayerKind
    let displayMode: MapDisplayMode
    let mapMode: MapMode
    let playerPinId: UUID?
    let pinScale: CGFloat
    let viewportScale: CGFloat

    var body: some View {
        switch kind {
        case .ordinary:
            ForEach(pins.ordinaryPinNodes) { node in
                MapPinLayerItem(
                    node: node,
                    displayMode: displayMode,
                    mapMode: mapMode,
                    playerPinId: playerPinId,
                    pinScale: pinScale,
                    viewportScale: viewportScale
                )
            }
        case .pointer:
            MapPinLayerItem(
                node: pins.pointerNode,
                displayMode: displayMode,
                mapMode: mapMode,
                playerPinId: playerPinId,
                pinScale: pinScale,
                viewportScale: viewportScale
            )
        case .zoomed:
            ForEach(pins.zoomedPinNodes) { node in
                MapPinLayerItem(
                    node: node,
                    displayMode: displayMode,
                    mapMode: mapMode,
                    playerPinId: playerPinId,
                    pinScale: pinScale,
                    viewportScale: viewportScale
                )
            }
        }
    }
}

private struct MapPinLayerItem: View {
    let node: MapPinNode
    let displayMode: MapDisplayMode
    let mapMode: MapMode
    let playerPinId: UUID?
    let pinScale: CGFloat
    let viewportScale: CGFloat

    private var isVisible: Bool {
        if node.isPointer, !node.pin.isShown { return false }
        return displayMode != .player || node.pin.isShown
    }

    private var canDrag: Bool {
        mapMode == .edit
            || mapMode == .gameMaster
            || (mapMode == .player && (node.id == playerPinId || node.isPointer))
    }

    private var actionContext: MapPinActionContext {
        guard !node.isPointer else { return .none }
        return switch mapMode {
        case .edit: .editor
        case .gameMaster: .gameMaster
        case .player, .viewer: .none
        }
    }

    private var doubleTapAccessibilityLabel: LocalizedStringResource {
        if node.isPointer || mapMode == .edit {
            LocalizedStringResource("Toggle Player Visibility", bundle: .module)
        } else {
            LocalizedStringResource("Show Pin Photo", bundle: .module)
        }
    }

    var body: some View {
        if isVisible {
            MapPinActionView(
                model: node,
                pinScale: pinScale,
                canDrag: canDrag,
                actionContext: actionContext,
                doubleTapAccessibilityLabel: doubleTapAccessibilityLabel,
                viewportScale: viewportScale
            )
            .allowsHitTesting(mapMode != .viewer)
        }
    }
}
