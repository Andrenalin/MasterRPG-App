// @copyright André Trettin

import CoreGraphics
import CoreRPG
import SwiftUI

// Split out of MapEditorModel.swift — see CODE_AUDIT §9.13.

extension MapEditorSession {
    // MARK: - Container Size Updates

    func updateContainerSize(_ newSize: CGSize) {
        guard newSize.isFiniteAndPositive else { return }
        guard measuredContainerSize != newSize else { return }
        measuredContainerSize = newSize
        updateEffectiveContainerSize()
    }

    /// Reserves only viewport geometry, never SwiftUI layout. The map canvas
    /// remains a full-window sibling of the game chrome while fit, focus, pan
    /// recovery, and viewport-space menus use the unobscured left-hand area.
    func updateTrailingViewportReservation(_ newReservation: CGFloat) {
        let reservation = newReservation.isFinite ? max(0, newReservation) : 0
        guard trailingViewportReservation != reservation else { return }
        trailingViewportReservation = reservation
        updateEffectiveContainerSize()
    }

    /// The editor canvas for `map` drawn over `image`, used on creation and on every update.
    /// See CODE_AUDIT_19 §9.13.
    static func canvasSize(map: MapModel, image: AKImage, degrees: Double) -> CGSize {
        MapCanvasGeometryResolver.resolve(
            map: map,
            mapSize: CGSize(width: map.width, height: map.height),
            imageSize: image.fixedSize,
            degrees: degrees
        )
    }

    func updateCanvas(map: MapModel, image: AKImage, photoDegrees: Double) {
        if mapId != map.id {
            changeImage(map: map)
        }
        let newCanvasSize = Self.canvasSize(map: map, image: image, degrees: photoDegrees)
        let geometryChanged = self.photoDegrees != photoDegrees
            || canvasSize != newCanvasSize
            || ObjectIdentifier(self.image) != ObjectIdentifier(image)

        self.image = image
        self.photoDegrees = photoDegrees
        canvasSize = newCanvasSize

        if completePendingInitialFitIfPossible() {
            return
        }
        if geometryChanged {
            viewport.configure(makeViewportConfiguration())
        }
    }

    // MARK: - Zooming

    func resetZoom() {
        viewport.reset()
    }

    func focusedMap() {
        guard let focusId else {
            resetZoom()
            return
        }

        guard let focusRoom = entries.roomNode(for: focusId) else {
            resetZoom()
            return
        }

        focus(on: focusRoom.bounds)
    }

    private func focus(on bounds: CGRect) {
        guard bounds.isFiniteAndPositive,
              containerSize.isFiniteAndPositive else {
            resetZoom()
            return
        }
        let sw = containerSize.width / (bounds.width + 50)
        let sh = containerSize.height / (bounds.height + 50)
        let newScale = min(sw, sh)

        withAnimation {
            let scale = viewport.geometry.clampedScale(newScale)
            viewport.commit(ViewportTransform(
                scale: scale,
                offset: CGPoint(
                    x: viewport.geometry.containerCenter.x - bounds.midX * scale,
                    y: viewport.geometry.containerCenter.y - bounds.midY * scale
                )
            ))
        }
    }

    func contentPoint(fromViewport point: CGPoint) -> CGPoint {
        viewport.geometry.contentPoint(fromViewport: point, transform: viewport.transform)
    }

    func viewportPoint(fromContent point: CGPoint) -> CGPoint {
        viewport.geometry.viewportPoint(fromContent: point, transform: viewport.transform)
    }

    func makeViewportConfiguration() -> ViewportConfiguration {
        ViewportConfiguration(
            id: mapId,
            contentSize: canvasSize,
            containerSize: containerSize,
            maximumScaleMultiplier: 8,
            panPolicy: .minimumVisible(44)
        )
    }

    private func updateEffectiveContainerSize() {
        let effectiveSize = Self.effectiveContainerSize(
            measuredSize: measuredContainerSize,
            trailingReservation: trailingViewportReservation
        )
        guard containerSize != effectiveSize else { return }
        containerSize = effectiveSize
        if completePendingInitialFitIfPossible() {
            return
        }
        // ViewportModel.resize refits a fitted map. At manual zoom it keeps
        // the logical point beneath the old available center beneath the new
        // available center, which is also the desired sidebar transition.
        viewport.resize(to: makeViewportConfiguration())
    }

    @discardableResult
    private func applyPendingInitialFitIfPossible() -> Bool {
        guard pendingInitialFitMapId == mapId,
              containerSize.isFiniteAndPositive,
              canvasSize.isFiniteAndPositive else { return false }
        let configuration = makeViewportConfiguration()
        if viewport.configuration != configuration {
            viewport.configure(configuration)
        } else {
            viewport.reset()
        }
        pendingInitialFitMapId = nil
        return true
    }

    @discardableResult
    func completePendingInitialFitIfPossible() -> Bool {
        guard applyPendingInitialFitIfPossible() else { return false }
        if presentationIsActive {
            appeared = true
        }
        return true
    }

    static func effectiveContainerSize(
        measuredSize: CGSize,
        trailingReservation: CGFloat
    ) -> CGSize {
        guard measuredSize.isFiniteAndPositive else { return .zero }
        let reservation = trailingReservation.isFinite
            ? max(0, trailingReservation)
            : 0
        let minimumRecoverableWidth = min(44, measuredSize.width)
        return CGSize(
            width: max(minimumRecoverableWidth, measuredSize.width - reservation),
            height: measuredSize.height
        )
    }

    var mapCanvasSize: CGSize { canvasSize }
}
