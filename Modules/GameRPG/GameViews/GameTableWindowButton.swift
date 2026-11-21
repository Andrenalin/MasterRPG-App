// @copyright André Trettin

#if !os(tvOS)
import CoreRPG
import SwiftUI

/// Toggles between the 2D map and the 3D table (iOS, macOS); see `GameTablePresentationController`.
@MainActor
struct GameTableWindowButton: View {
    let root: GameRoot
#if !os(visionOS)
    @Environment(AppSettingsModel.self) private var appSettingsModel

    private var controller: GameTablePresentationController {
        GameTablePresentationController(root: root, appSettingsModel: appSettingsModel)
    }
#endif

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
#if os(visionOS)
        // The table is the game on visionOS: there is no 2D map to switch back to.
        EmptyView()
#else
        Button(action: controller.toggle) {
            Label {
                Text(actionTitle)
            } icon: {
                Image(systemName: "cube.transparent")
            }
        }
        .selectedRoundButton(
            title: String(localized: actionTitle),
            module: .map,
            isSelected: isPresented
        )
#endif
    }

#if !os(visionOS)
    private var isPresented: Bool { controller.isPresented }

    private var actionTitle: LocalizedStringResource {
        isPresented
            ? LocalizedStringResource("Show 2D Map", bundle: .module)
            : LocalizedStringResource("Show 3D Table", bundle: .module)
    }
#endif
}

#Preview(traits: .mockData) {
    GameTableWindowButton(root: .preview)
}
#endif
