// @copyright André Trettin

import CoreRPG
import Testing

@testable import RolePlayGameKit

/// CODE_AUDIT_26 §5.47: Photo with no image has nothing to save.
@Suite("Share extension save rule")
struct ShareExtensionSaveRuleTests {
    @Test("Photo needs at least one image")
    func photoNeedsAnImage() {
        #expect(!ShareExtensionError.canSave(to: .photo, imageCount: 0))
        #expect(ShareExtensionError.canSave(to: .photo, imageCount: 1))
    }

    @Test("Other modules save text without images")
    func otherModulesSaveText() {
        for module in [NetworkModules.adventure, .value, .map, .weather] {
            #expect(ShareExtensionError.canSave(to: module, imageCount: 0))
        }
    }

    @Test("The no-photo error has a readable description")
    func noPhotoErrorDescription() {
        #expect(ShareExtensionError.noPhotoToSave.errorDescription?.isEmpty == false)
    }
}
