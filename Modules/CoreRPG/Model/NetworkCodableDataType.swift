// @copyright André Trettin

import Foundation
import SwiftUI

public extension EnvironmentValues {
    @Entry var networkActions: NetworkActions? = nil

    /// True only while an actual SharePlay `GroupSession` is active for the
    /// current game. Unlike `networkActions` — present for solo, local-network,
    /// *and* SharePlay sessions alike — this specifically gates behavior that
    /// depends on visionOS's system-provided spatial-persona coordinate
    /// alignment across SharePlay participants (e.g. SpaceViewer's shared
    /// immersive placement, which must stay head-anchored otherwise).
    @Entry var isSpaceSharePlayActive: Bool = false
}

/// Shared wall-clock admission policy for event timestamps arriving over the
/// network (map pins, Space transforms, generic game envelopes). Previously
/// declared independently in three places with two different spellings of
/// the same five-minute value — consolidated here so a change to the
/// tolerance can't silently apply to only one transport.
/// See CODE_AUDIT_Game §9.12.
public enum NetworkTimestampPolicy {
    /// Bounds wall-clock ordering input before it can become the
    /// presentation baseline. A timestamp more than this far in this
    /// device's future is rejected as implausible.
    public static let maximumFutureSkew: TimeInterval = 300
}

public struct NetworkActions: Sendable {
    public let shareId: @MainActor @Sendable (NetworkCodableDataType) -> Void
    public let send: @MainActor @Sendable (NetworkCodableDataType) -> Void
    public let game: @MainActor @Sendable (NetworkCodableDataType, RPGMessageActionType, UUID?) -> Void

    public init(shareId: @MainActor @escaping @Sendable (NetworkCodableDataType) -> Void, send: @MainActor @escaping @Sendable (NetworkCodableDataType) -> Void, game: @MainActor @escaping @Sendable (NetworkCodableDataType, RPGMessageActionType, UUID?) -> Void) {
        self.shareId = shareId
        self.send = send
        self.game = game
    }
    
    @MainActor static let empty = NetworkActions(shareId: { _ in }, send: { _ in }, game: { _, _, _ in })
}

public struct NetworkCodableDataType: Codable, Sendable, Equatable, MessageMapper {
    public init(
        id: UUID,
        type: NetworkModules,
        version: Int,
        data: Data? = nil,
        assetVersion: Int? = nil,
        contentVersion: Int? = nil
    ) {
        self.id = id
        self.type = type
        self.version = version
        self.data = data
        self.assetVersion = assetVersion
        self.contentVersion = contentVersion
    }

    public let id: UUID
    public let type: NetworkModules
    public let version: Int
    public let data: Data?
    /// Version of the file-backed asset independently from mutable item
    /// metadata. Older peers ignore this optional key and continue using
    /// `version`, while current map transport uses it to decide whether the
    /// SharePlay Journal attachment must be replaced.
    public let assetVersion: Int?
    /// Version of the photo-free mutable metadata represented by `data`.
    public let contentVersion: Int?

    public var effectiveAssetVersion: Int { assetVersion ?? version }

    public static let empty = NetworkCodableDataType(id: UUID(), type: .none, version: 0, data: nil)
}

