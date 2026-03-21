// @copyright André Trettin

import CoreRPG
import CoreGraphics
import Foundation
import GroupActivities

public struct RPGActivity: GroupActivity, Sendable {
    public static let activityIdentifier = "de.andretrettin.MasterRPG.play-rpg-together"
    @MainActor static var titleImage: CGImage?

    var adventureTitle: String = NSLocalizedString("Play Pen&Paper RPG", bundle: .module, comment: "Title of group activity")

    @MainActor public var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .generic
        metadata.title = adventureTitle
        metadata.subtitle = NSLocalizedString("Play Pen&Paper RPG", bundle: .module, comment: "Title of group activity")
        metadata.supportsContinuationOnTV = false
        metadata.previewImage = Self.titleImage

        return metadata
    }
}
