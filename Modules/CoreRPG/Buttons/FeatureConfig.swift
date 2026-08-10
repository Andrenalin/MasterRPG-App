// @copyright André Trettin

import SwiftUI

public struct GameFeatureModel: Equatable, Hashable, Codable, Sendable {
    public init(diceMaster: Bool = true, dicePlayers: Bool = true, audioSharing: Bool = true, photoSharing: Bool = true, spaceSharing: Bool = true) {
        self.diceMaster = diceMaster
        self.dicePlayers = dicePlayers
        self.audioSharing = audioSharing
        self.photoSharing = photoSharing
        self.spaceSharing = spaceSharing
    }
    
    public var diceMaster: Bool
    public var dicePlayers: Bool
    public var audioSharing: Bool
    public var photoSharing: Bool
    public var spaceSharing: Bool
}

public struct SharingFeatureActions: Equatable, Sendable {
    /// `id` should be stable across the writer's re-renders (e.g. the owning
    /// root model's `ObjectIdentifier`) so SwiftUI's environment diffing can
    /// skip invalidating readers when the same root writes the same
    /// functional closure again. See CODE_AUDIT §8.8.
    public init(id: EnvironmentActionIdentity = .fresh(), features: @MainActor @escaping @Sendable () -> GameFeatureModel) {
        self.id = id
        self.features = features
    }

    let id: EnvironmentActionIdentity
    public let features: (@MainActor @Sendable () -> GameFeatureModel)

    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.id == rhs.id
    }
}

public extension EnvironmentValues {
    var sharingFeatureActions: SharingFeatureActions {
        get { self[SharingFeatureActionsKey.self] }
        set { self[SharingFeatureActionsKey.self] = newValue }
    }
}

struct SharingFeatureActionsKey: EnvironmentKey {
    static let defaultValue = SharingFeatureActions(features: { GameFeatureModel() })
}

