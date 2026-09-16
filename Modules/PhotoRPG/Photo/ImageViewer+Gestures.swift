// @copyright André Trettin

import CoreRPG
import SwiftUI

// Extracted from ImageViewer.swift — a separable, platform-conditional chunk with its
// own MARK boundary. See CODE_AUDIT §9.10.
#if !os(tvOS)
// MARK: - Gesture session

extension ImageViewer {
    typealias ViewportGesture = SimultaneousGesture<MagnifyGesture, DragGesture>

    var viewportGesture: some Gesture {
        MagnifyGesture(minimumScaleDelta: 0)
            .simultaneously(with: DragGesture(minimumDistance: 3, coordinateSpace: .local))
            .updating($gestureSession, body: updateGestureSession(_:state:transaction:))
            .onEnded(commitGestureSession(_:))
    }

    var doubleTapGesture: some Gesture {
        SpatialTapGesture(count: 2, coordinateSpace: .local)
            .onEnded(doubleTap(_:))
    }

    func updateGestureSession(
        _ value: ViewportGesture.Value,
        state: inout ImageViewportGestureSession,
        transaction _: inout Transaction
    ) {
        if let magnify = value.first {
            state.magnification = magnify.magnification
            state.anchor = magnify.startLocation
        }
        if let drag = value.second {
            state.translation = drag.translation
        }
    }

    func commitGestureSession(_ value: ViewportGesture.Value) {
        let transform = geometry.viewportGeometry.interacting(
            from: viewportModel.transform,
            translation: value.second?.translation ?? gestureSession.translation,
            magnification: value.first?.magnification ?? gestureSession.magnification,
            anchor: value.first?.startLocation
                ?? gestureSession.anchor
                ?? geometry.viewportGeometry.containerCenter
        )
        apply(transform, animated: false)
    }

    func doubleTap(_ value: SpatialTapGesture.Value) {
        let transform = geometry.viewportGeometry.doubleTapped(
            from: viewportModel.transform,
            at: value.location
        )
        apply(transform, animated: true)
    }
}

struct ImageViewportGestureSession: Equatable {
    var translation = CGSize.zero
    var magnification: CGFloat = 1
    var anchor: CGPoint?
}
#endif
