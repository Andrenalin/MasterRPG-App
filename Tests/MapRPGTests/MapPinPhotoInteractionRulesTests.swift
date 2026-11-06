// @copyright André Trettin

#if canImport(Testing)
import Foundation
import Testing

@testable import MapRPG

/// CODE_AUDIT_24 §9.4: the rules both the 2D map and the 3D table apply to the pin photo.
struct MapPinPhotoInteractionRulesTests {
    private func pin(isShown: Bool = true, isPhotoShared: Bool = false) -> MapPinModel {
        MapPinModel(id: UUID(), name: "Ogre", isShown: isShown, isPhotoShared: isPhotoShared)
    }

    @Test("The game master shares the photo of a shown pin the players see, and ends it on the next tap")
    func gameMasterSharesVisiblePin() {
        let open = MapPinPhotoSharing.doubleTap(on: pin(), isGameMaster: true, isPopoverOpen: false, isVisibleToPlayers: true)
        #expect(open == .init(showsPopover: true, sharedFlag: true))

        let close = MapPinPhotoSharing.doubleTap(on: pin(isPhotoShared: true), isGameMaster: true, isPopoverOpen: true, isVisibleToPlayers: true)
        #expect(close == .init(showsPopover: false, sharedFlag: false))
    }

    @Test("A pin the players cannot see (fog) or a hidden pin opens on the game master's device only")
    func gameMasterKeepsInvisiblePinLocal() {
        let fogged = MapPinPhotoSharing.doubleTap(on: pin(), isGameMaster: true, isPopoverOpen: false, isVisibleToPlayers: false)
        #expect(fogged == .init(showsPopover: true, sharedFlag: false), "no share; a stale flag is cleared")

        let hidden = MapPinPhotoSharing.doubleTap(on: pin(isShown: false), isGameMaster: true, isPopoverOpen: false, isVisibleToPlayers: false)
        #expect(hidden == .init(showsPopover: true, sharedFlag: nil), "nothing to change on a hidden pin")

        // A flag left on a pin that has since been hidden is still ended.
        let stale = MapPinPhotoSharing.doubleTap(on: pin(isShown: false, isPhotoShared: true), isGameMaster: true, isPopoverOpen: true, isVisibleToPlayers: false)
        #expect(stale == .init(showsPopover: false, sharedFlag: false))
    }

    @Test("A player opens only the photos of pins on the map, and never changes the shared flag")
    func playerStaysLocal() {
        #expect(MapPinPhotoSharing.doubleTap(on: pin(isShown: false), isGameMaster: false, isPopoverOpen: false, isVisibleToPlayers: false) == nil)
        let tap = MapPinPhotoSharing.doubleTap(on: pin(isPhotoShared: true), isGameMaster: false, isPopoverOpen: false, isVisibleToPlayers: true)
        #expect(tap == .init(showsPopover: true, sharedFlag: nil))
        let close = MapPinPhotoSharing.doubleTap(on: pin(), isGameMaster: false, isPopoverOpen: true, isVisibleToPlayers: true)
        #expect(close == .init(showsPopover: false, sharedFlag: nil))
    }

    @Test("Closing the popover ends the photo for everyone only when the game master shared it")
    func dismissEndsSharingForGameMasterOnly() {
        #expect(MapPinPhotoSharing.dismissEndsSharing(of: pin(isPhotoShared: true), isGameMaster: true))
        #expect(!MapPinPhotoSharing.dismissEndsSharing(of: pin(), isGameMaster: true))
        #expect(!MapPinPhotoSharing.dismissEndsSharing(of: pin(isPhotoShared: true), isGameMaster: false))
        #expect(!MapPinPhotoSharing.dismissEndsSharing(of: nil, isGameMaster: true))
    }
}
#endif
