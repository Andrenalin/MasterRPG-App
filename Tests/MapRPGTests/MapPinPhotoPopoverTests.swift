// @copyright André Trettin

#if canImport(Testing)
import CoreGraphics
import Foundation
import Testing

@testable import MapRPG

@Suite("Pin photo popover")
@MainActor
struct MapPinPhotoPopoverTests {
    @Test("Only a change of the shared flag shows or hides the photo")
    func sharingChangeIsTransitionOnly() {
        #expect(MapPinPhotoSharing.change(wasShared: false, isShared: true) == .show)
        #expect(MapPinPhotoSharing.change(wasShared: true, isShared: false) == .hide)
        #expect(MapPinPhotoSharing.change(wasShared: false, isShared: false) == nil)
        // A flag that was already on when the map opened must not pop up by itself.
        #expect(MapPinPhotoSharing.change(wasShared: true, isShared: true) == nil)
    }

    @Test("A double tap toggles the local popover without emitting map changes")
    func localToggle() throws {
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        let model = MapPinViewModel(mapPins: [pin], pointer: .empty)

        model.togglePhoto(pinId: pin.id)
        #expect(model.photoPinId == pin.id)

        model.togglePhoto(pinId: pin.id)
        #expect(model.photoPinId == nil)
        #expect(try #require(model.pinNode(for: pin.id)).pin.isZoom == false)
    }

    @Test("The master's shared flag opens and closes the popover")
    func sharedFlagOpensAndClosesPopover() throws {
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        let model = MapPinViewModel(mapPins: [pin], pointer: .empty)

        var shared = pin
        shared.isZoom = true
        model.setPinPointer(updatedPin: shared)
        #expect(model.photoPinId == pin.id)

        model.setPinPointer(updatedPin: pin)
        #expect(model.photoPinId == nil)
    }

    @Test("A full map sync opens the popover only for a changed flag")
    func reconcileOpensPopoverOnChangeOnly() {
        var staleShared = MapPinModel(id: UUID(), name: "Stale")
        staleShared.isZoom = true
        let other = MapPinModel(id: UUID(), name: "Other")
        let model = MapPinViewModel(mapPins: [staleShared, other], pointer: .empty)
        #expect(model.photoPinId == nil)

        // The same state arriving again changes nothing.
        model.mapPins = [staleShared, other]
        #expect(model.photoPinId == nil)

        var nowShared = other
        nowShared.isZoom = true
        model.mapPins = [staleShared, nowShared]
        #expect(model.photoPinId == other.id)

        model.mapPins = [staleShared, other]
        #expect(model.photoPinId == nil)
    }

    @Test("A player closing a shared photo locally keeps it closed until the flag changes again")
    func localCloseSurvivesRepeatedSync() {
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        let model = MapPinViewModel(mapPins: [pin], pointer: .empty)
        var shared = pin
        shared.isZoom = true
        model.mapPins = [shared]
        #expect(model.photoPinId == pin.id)

        model.setPhotoPinId(nil)
        model.mapPins = [shared]
        #expect(model.photoPinId == nil)
    }

    @Test("The photo and the action menu of one pin exclude each other")
    func photoAndMenuExcludeEachOther() {
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        let model = MapPinViewModel(mapPins: [pin], pointer: .empty)

        model.isExpandedId = pin.id
        model.togglePhoto(pinId: pin.id)
        #expect(model.photoPinId == pin.id)
        #expect(model.isExpandedId == nil)

        model.isExpandedId = pin.id
        #expect(model.photoPinId == nil)
        #expect(model.isExpandedId == pin.id)
    }

    @Test("Removing the pin closes its photo popover")
    func removingPinClosesPopover() {
        let pin = MapPinModel(id: UUID(), name: "Goblin")
        let model = MapPinViewModel(mapPins: [pin], pointer: .empty)
        model.togglePhoto(pinId: pin.id)

        model.mapPins = []

        #expect(model.photoPinId == nil)
    }
}
#endif
