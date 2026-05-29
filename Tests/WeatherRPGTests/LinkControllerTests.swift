// @copyright André Trettin

import CoreRPG
import Foundation
import RPGResourcesDebug
import Testing

@testable import WeatherRPG
@testable import PhotoRPG

@Suite("Weather link validation — photo links")
@MainActor
struct LinkControllerTests {

    // MARK: - Stale link

    @Test("validateLinks clears photoId when the referenced photo does not exist")
    func validatePhotoLinkClearsStaleLink() async throws {
        let root = WeatherRootModel.testRoot(photoRoot: PhotoFactory.root(tagController: .preview))
        let weatherId = await root.itemController.addNew(type: .scenario)
        let weatherModel = try #require(root.itemController.itemSync(for: weatherId))
        weatherModel.photoId = UUID()  // ghost — no photo with this ID exists in photoRoot

        root.linkController.validateLinks(on: weatherId)

        let after = try #require(root.itemController.itemSync(for: weatherId))
        #expect(after.photoId == nil)
    }

    // MARK: - Valid link

    @Test("validateLinks preserves photoId when the referenced photo exists")
    func validatePhotoLinkKeepsValidLink() async throws {
        let root = WeatherRootModel.testRoot(photoRoot: PhotoFactory.root(tagController: .preview))
        let photoId = await root.photoRoot.itemController.addNew(type: .item)
        let weatherId = await root.itemController.addNew(type: .scenario)
        let weatherModel = try #require(root.itemController.itemSync(for: weatherId))
        weatherModel.photoId = photoId

        root.linkController.validateLinks(on: weatherId)

        let after = try #require(root.itemController.itemSync(for: weatherId))
        #expect(after.photoId == photoId)
    }

    // MARK: - No link

    @Test("validateLinks leaves photoId nil when no photo is linked")
    func validatePhotoLinkIsNoOpForNilPhotoId() async throws {
        let root = WeatherRootModel.testRoot(photoRoot: PhotoFactory.root(tagController: .preview))
        let weatherId = await root.itemController.addNew(type: .scenario)

        root.linkController.validateLinks(on: weatherId)

        let after = try #require(root.itemController.itemSync(for: weatherId))
        #expect(after.photoId == nil)
    }

    // MARK: - Link register deregistration

    @Test("validateLinks removes the photo link from linkRegisterController when the photo is gone")
    func validateLinksDeregistersStalePhotoLink() async throws {
        let root = WeatherRootModel.testRoot(photoRoot: PhotoFactory.root(tagController: .preview))

        // Add a real photo and a weather item, then link them via the edit controller so
        // saveChanges() fires changedLinkRegisterModels() and registers the link.
        let photoId = await root.photoRoot.itemController.addNew(type: .item)
        let weatherId = await root.itemController.addNew(type: .scenario)
        root.editController.add(photoId: photoId, itemId: weatherId)

        let photoDestination = ItemRowModel(itemId: photoId, typeId: .photo)

        // Precondition: the link must be present in the in-memory register.
        #expect(root.itemControllable.linkRegisterController.isUsed(link: photoDestination))

        // Simulate photo deletion without using EditController.delete —
        // remove the photo from the photo root's in-memory data model directly.
        root.photoRoot.itemController.itemDataModel.items.removeAll { $0 == photoId }
        root.photoRoot.itemController.itemDataModel.itemData[photoId] = nil

        // Act: validateLinks detects the missing photo, nils out photoId, and
        // calls resetLinkRegister which deregisters the stale link.
        root.linkController.validateLinks(on: weatherId)

        // The weather item's photoId must have been cleared.
        let after = try #require(root.itemController.itemSync(for: weatherId))
        #expect(after.photoId == nil)

        // The link must be absent from the in-memory register (DB is nil in test, so in-memory is the full store).
        #expect(!root.itemControllable.linkRegisterController.isUsed(link: photoDestination))
        #expect(root.itemControllable.linkRegisterController.model.items[photoId, default: []].isEmpty)
    }
}
