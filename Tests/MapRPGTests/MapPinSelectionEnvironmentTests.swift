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

        show(picker)
    }

    @Test("The photo picker does not rely on the presenter's module roots")
    func photoPickerBringsItsRoots() async throws {
        let root = try await MockRoot.importTestData()
        let picker = root.viewController.photoSelection(
            root: root,
            selectionModel: ItemSelectionModel(isSingleSelection: false, allowCollections: false)
        )

        show(picker)
    }

    /// Sizes `picker` once with the volumetric window's environment only. Sizing evaluates the
    /// body, which is where a missing module root is a fatal error; no window is needed for that.
    private func show(_ picker: some View) {
        let content = picker
            .environment(ScenesManager())
            .environment(AppSettingsModel())
            .environment(AppGameStateModel())
            .setAppSizeMode()
        let controller = UIHostingController(rootView: content)
        _ = controller.sizeThatFits(in: CGSize(width: 600, height: 800))
    }
}
#endif
