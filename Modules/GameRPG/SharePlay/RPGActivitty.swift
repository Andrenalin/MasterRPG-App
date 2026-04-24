// @copyright André Trettin

import CoreRPG
import CoreTransferable
import CoreGraphics
import Foundation
import GroupActivities

public struct RPGActivity: GroupActivity, Sendable {
    public init(adventureTitle: String? = nil) {
        if let adventureTitle {
            self.adventureTitle = adventureTitle
        }
    }
    
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
        #if os(visionOS)
        metadata.sceneAssociationBehavior = .content(SceneId.gameTable.rawValue)
        #endif

        return metadata
    }
}

#if !os(tvOS)
extension RPGActivity: Transferable {}
#endif
