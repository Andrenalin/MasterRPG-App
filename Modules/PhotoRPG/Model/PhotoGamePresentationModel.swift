// @copyright André Trettin

import Foundation
import Observation

/// The photo the running game actively shows. Only a show-photo event sets it; a photo that
/// was merely stored (a map's pin photos, an asset repair, a saved-game load) never does.
///
/// The visionOS 3D image viewer follows this model instead of `ItemGameModel.currentItemId`:
/// that is just the first cached game item, so a stored photo landing in an empty list became
/// "current" and popped the viewer open for a photo nobody revealed.
@MainActor @Observable
public final class PhotoGamePresentationModel {
    public init() {}

    public private(set) var presentedItemId: UUID?

    public func present(itemId: UUID) {
        presentedItemId = itemId
    }

    public func reset() {
        presentedItemId = nil
    }
}
