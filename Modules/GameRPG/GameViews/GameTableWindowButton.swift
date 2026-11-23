// @copyright André Trettin

#if !os(tvOS) && !os(visionOS)
import CoreRPG
import SwiftUI

/// Toggles between the 2D map and the 3D table (iOS, macOS; the table is the game on visionOS); see `GameTablePresentationController`.
@MainActor
struct GameTableWindowButton: View {
    let root: GameRoot
    @Environment(AppSettingsModel.self) private var appSettingsModel

    private var controller: GameTablePresentationController {
        GameTablePresentationController(root: root, appSettingsModel: appSettingsModel)
    }

    var body: some View {
        let _ = Self.printViewChangesOnlyInDebug()
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
    }

    private var isPresented: Bool { controller.isPresented }

    private var actionTitle: LocalizedStringResource {
        isPresented
            ? LocalizedStringResource("Show 2D Map", bundle: .module)
            : LocalizedStringResource("Show 3D Table", bundle: .module)
    }
}

#Preview(traits: .mockData) {
    GameTableWindowButton(root: .preview)
}
#endif
