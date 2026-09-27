// @copyright André Trettin

import CoreRPG
import CoreTransferable
import CoreGraphics
import Foundation
import GroupActivities

public struct RPGActivity: GroupActivity, Sendable {
    public init(adventureTitle: String? = nil, activationId: UUID? = nil) {
        if let adventureTitle {
            self.adventureTitle = adventureTitle
        }
        self.activationId = activationId
    }
    
    public static let activityIdentifier = BundleIds.app("play-rpg-together")
    @MainActor static var titleImage: CGImage?

    var adventureTitle: String = String(
        localized: "Play Pen&Paper RPG",
        bundle: .module,
        comment: "Title of group activity"
    )
    /// Identifies a local activation attempt so a late session from a cancelled
    /// start can be left without rejecting unrelated remote invitations.
    var activationId: UUID?

    @MainActor public var metadata: GroupActivityMetadata {
        var metadata = GroupActivityMetadata()
        metadata.type = .generic
        metadata.title = adventureTitle
        metadata.subtitle = String(
            localized: "Play Pen&Paper RPG",
            bundle: .module,
            comment: "Title of group activity"
        )
        metadata.supportsContinuationOnTV = false
        metadata.previewImage = Self.titleImage
        #if os(visionOS)
        metadata.sceneAssociationBehavior = .content(SceneId.gameTable.rawValue)
        #endif

        return metadata
    }
}

#if !os(tvOS)
extension RPGActivity: Transferable {}
#endif
