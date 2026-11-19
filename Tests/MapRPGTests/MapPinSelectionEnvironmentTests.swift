// @copyright André Trettin

#if canImport(Testing) && canImport(UIKit)
import CoreRPG
import SwiftUI
import Testing
import UIKit

@testable import MapRPG

/// The pickers of the game toolbar's "Choose Map Pins" menu are presented from places that inject
/// few environment values: the visionOS 3D table's volumetric window gives its toolbar only the
/// scenes manager, the settings, the game state, the window size and the network actions. A
/// module root the picker reads and does not find is a fatal error ("No Observable object of type
/// CharacterRootModel found"), so these tests host the pickers with exactly that much.
@Suite("Map pin selection environment")
@MainActor
struct MapPinSelectionEnvironmentTests {
    @Test("The character picker does not rely on the presenter's module roots")
    func characterPickerBringsItsRoots() async throws {
        let root = try await MockRoot.importTestData()
        let picker = root.viewController.characterSelection(
            root: root,
            selectionModel: ItemSelectionModel(isSingleSelection: false, allowCollections: true)
        )

        try await show(picker)
    }

    @Test("The photo picker does not rely on the presenter's module roots")
    func photoPickerBringsItsRoots() async throws {
        let root = try await MockRoot.importTestData()
        let picker = root.viewController.photoSelection(
            root: root,
            selectionModel: ItemSelectionModel(isSingleSelection: false, allowCollections: false)
        )

        try await show(picker)
    }

    /// Puts `picker` on screen in a window with the volumetric window's environment only.
    private func show(_ picker: some View) async throws {
        let content = picker
            .environment(ScenesManager())
            .environment(AppSettingsModel())
            .environment(AppGameStateModel())
            .setAppSizeMode()
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 600, height: 800))
        window.rootViewController = UIHostingController(rootView: content)
        window.makeKeyAndVisible()
        window.layoutIfNeeded()
        // The picker's rows are made on the first passes of the run loop.
        try await Task.sleep(for: .milliseconds(300))
        window.isHidden = true
    }
}
#endif
