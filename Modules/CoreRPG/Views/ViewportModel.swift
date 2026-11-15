// @copyright André Trettin

import CoreGraphics
import Foundation
import Observation

// Split out of ViewportGeometry.swift — see CODE_AUDIT_19 §9.23.

/// A narrow observable owner for committed viewport state. Transient gesture transforms should
/// stay in `@GestureState` and be committed here once when the interaction ends.
@MainActor @Observable public final class ViewportModel {
    private var state: State

    public init(
        configuration: ViewportConfiguration,
        transform: ViewportTransform? = nil
    ) {
        let geometry = ViewportGeometry(configuration: configuration)
        state = State(
            configuration: configuration,
            transform: geometry.constrained(transform ?? geometry.fitTransform)
        )
    }

    public var configuration: ViewportConfiguration {
        state.configuration
    }

    public var transform: ViewportTransform {
        state.transform
    }

    public var geometry: ViewportGeometry {
        ViewportGeometry(configuration: state.configuration)
    }

    public var isAtFit: Bool {
        geometry.isAtFit(state.transform)
    }

    public func commit(_ transform: ViewportTransform) {
        let constrained = geometry.constrained(transform)
        guard constrained != state.transform else {
            return
        }
        state = State(configuration: state.configuration, transform: constrained)
    }

    public func reset() {
        commit(geometry.fitTransform)
    }

    /// Zooms about the center of the viewport, for menu and keyboard commands. A factor above 1
    /// zooms in. The scale stays within the geometry's limits.
    public func zoom(by factor: CGFloat) {
        let geometry = geometry
        commit(geometry.magnified(from: state.transform, magnification: factor, anchor: geometry.containerCenter))
    }

    public func configure(_ configuration: ViewportConfiguration) {
        guard configuration != state.configuration else {
            return
        }
        let geometry = ViewportGeometry(configuration: configuration)
        state = State(configuration: configuration, transform: geometry.fitTransform)
    }

    public func resize(
        to configuration: ViewportConfiguration,
        oldAnchor: CGPoint? = nil,
        newAnchor: CGPoint? = nil,
        refitWhenAtFit: Bool = true
    ) {
        guard configuration != state.configuration else {
            return
        }
        let geometry = ViewportGeometry(configuration: configuration)
        let transform = geometry.resizedTransform(
            from: state.transform,
            previousConfiguration: state.configuration,
            oldAnchor: oldAnchor,
            newAnchor: newAnchor,
            refitWhenAtFit: refitWhenAtFit
        )
        state = State(configuration: configuration, transform: transform)
    }
}

private extension ViewportModel {
    struct State: Equatable {
        let configuration: ViewportConfiguration
        let transform: ViewportTransform
    }
}
