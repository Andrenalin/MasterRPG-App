// @copyright André Trettin

import CoreGraphics
import Foundation
import Observation

// Split out of ViewportGeometry.swift — see CODE_AUDIT_19 §9.23.

/// The committed transform of logical content inside a viewport.
public struct ViewportTransform: Equatable, Sendable {
    public init(scale: CGFloat = 1, offset: CGPoint = .zero) {
        self.scale = scale
        self.offset = offset
    }

    public var scale: CGFloat
    public var offset: CGPoint

    public static let identity = ViewportTransform()
}

/// Defines how far transformed content may be moved outside its viewport.
public enum ViewportPanPolicy: Equatable, Sendable {
    /// Small content is centered and large content continues to cover the viewport.
    case contained

    /// Content may leave the viewport while this many points remain recoverable on each axis.
    case minimumVisible(CGFloat)
}

/// Immutable inputs used to calculate a viewport transform.
public struct ViewportConfiguration: Equatable, Sendable {
    public init(
        id: UUID,
        contentSize: CGSize,
        containerSize: CGSize,
        maximumScaleMultiplier: CGFloat = 8,
        panPolicy: ViewportPanPolicy = .contained
    ) {
        self.id = id
        self.contentSize = contentSize.validViewportSize
        self.containerSize = containerSize.validViewportSize
        self.maximumScaleMultiplier = maximumScaleMultiplier.validScaleMultiplier
        self.panPolicy = panPolicy.validViewportPolicy
    }

    public let id: UUID
    public let contentSize: CGSize
    public let containerSize: CGSize
    public let maximumScaleMultiplier: CGFloat
    public let panPolicy: ViewportPanPolicy
}
