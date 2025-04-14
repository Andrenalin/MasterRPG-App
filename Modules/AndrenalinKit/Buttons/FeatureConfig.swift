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

public struct SharingFeatureActions {
    public init(features: @escaping () -> GameFeatureModel) {
        self.features = features
    }

    public let features: (() -> GameFeatureModel)
}

public extension EnvironmentValues {
    var sharingFeatureActions: SharingFeatureActions {
        get { self[SharingFeatureActionsKey.self] }
        set { self[SharingFeatureActionsKey.self] = newValue }
    }
}

struct SharingFeatureActionsKey: EnvironmentKey {
    nonisolated(unsafe) static let defaultValue = SharingFeatureActions(features: { GameFeatureModel() })
}

